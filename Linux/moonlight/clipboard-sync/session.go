package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"
)

var errBusy = errors.New("another clipboard client is active")

type agentLock struct{ f *os.File }

func (l *agentLock) Close() error { return l.f.Close() }
func AgentLock(runtimeDir string) (io.Closer, error) {
	fd, err := syscall.Open(filepath.Join(runtimeDir, "moonlight-clipboard.lock"), syscall.O_CREAT|syscall.O_RDWR|syscall.O_CLOEXEC|syscall.O_NOFOLLOW, 0600)
	if err != nil {
		return nil, err
	}
	f := os.NewFile(uintptr(fd), "clipboard lock")
	if err = syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		f.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) {
			return nil, errBusy
		}
		return nil, err
	}
	return &agentLock{f}, nil
}
func sessionSocket(env map[string]string) string {
	socket := env["WAYLAND_DISPLAY"]
	if filepath.IsAbs(socket) {
		return socket
	}
	return filepath.Join(env["XDG_RUNTIME_DIR"], socket)
}

type streamTransport struct {
	in  io.ReadCloser
	out io.WriteCloser
}

func (t *streamTransport) Read() (Frame, error) { return ReadFrame(t.in) }
func (t *streamTransport) Write(f Frame) error  { return WriteFrame(t.out, f) }
func (t *streamTransport) Close() error         { t.out.Close(); return t.in.Close() }

// Limit diagnostics independently of frame payloads; never print their content.
type limitedDiagnostics struct{ bytes.Buffer }

func (b *limitedDiagnostics) Write(p []byte) (int, error) {
	n := len(p)
	if b.Len() < 4096 {
		end := min(len(p), 4096-b.Len())
		b.Buffer.Write(p[:end])
	}
	return n, nil
}

func runCommandSession(ctx context.Context, cmd *exec.Cmd, cb Clipboard) error {
	in, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	out, err := cmd.StdinPipe()
	if err != nil {
		in.Close()
		return err
	}
	diagnostic := &limitedDiagnostics{}
	cmd.Stderr = diagnostic
	cmd.WaitDelay = 2 * time.Second
	if err = cmd.Start(); err != nil {
		in.Close()
		out.Close()
		return err
	}
	transport := &streamTransport{in, out}
	err = RunCoordinator(ctx, cb, transport)
	transport.Close()
	// Kill only this SSH channel process, never its shared ControlMaster.
	_ = cmd.Process.Signal(syscall.SIGTERM)
	exited := make(chan error, 1)
	go func() { exited <- cmd.Wait() }()
	var exitErr error
	select {
	case exitErr = <-exited:
	case <-time.After(2 * time.Second):
		_ = cmd.Process.Kill()
		exitErr = <-exited
	}
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if exitErr != nil {
		s := diagnostic.String()
		for _, needle := range []string{"Permission denied", "Host key verification failed", "REMOTE HOST IDENTIFICATION HAS CHANGED", "command not found", "No such file or directory"} {
			if strings.Contains(s, needle) {
				return &permanentError{"SSH authentication, host key, or remote helper unavailable"}
			}
		}
	}
	if err != nil {
		return err
	}
	return exitErr
}

type permanentError struct{ message string }

func (e *permanentError) Error() string { return e.message }

func RunClient(ctx context.Context, host string) error {
	if !regexp.MustCompile(`^[A-Za-z0-9_][A-Za-z0-9_.@:-]*$`).MatchString(host) {
		return &permanentError{"invalid SSH target"}
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	socket := sessionSocket(map[string]string{"WAYLAND_DISPLAY": os.Getenv("WAYLAND_DISPLAY"), "XDG_RUNTIME_DIR": os.Getenv("XDG_RUNTIME_DIR")})
	if os.Getenv("WAYLAND_DISPLAY") == "" {
		return &permanentError{"launch clipboard sync from your graphical session"}
	}
	delay := time.Second
	failures := 0
	for {
		cmd := exec.CommandContext(ctx, "/usr/bin/ssh", "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "ConnectionAttempts=1",
			"-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=3", "-o", "ControlMaster=auto", "-o", "ControlPersist=60",
			"-o", "ControlPath="+filepath.Join(home, ".ssh", "cm-%C"), "--", host, ".local/bin/moonlight-clipboard agent")
		started := time.Now()
		err = runCommandSession(ctx, cmd, NewWaylandClipboard(socket))
		if ctx.Err() != nil {
			return ctx.Err()
		}
		notify("Clipboard sync disconnected; video streaming is unaffected.")
		var permanent *permanentError
		if errors.As(err, &permanent) || errors.Is(err, errFrame) || err != nil && strings.HasPrefix(err.Error(), "remote clipboard:") || err != nil && strings.HasPrefix(err.Error(), "clipboard unavailable:") {
			return err
		}
		if time.Since(started) > 30*time.Second {
			failures = 0
			delay = time.Second
		}
		failures++
		if failures >= 5 {
			return errors.New("clipboard connection failed repeatedly; relaunch Moonlight to retry")
		}
		timer := time.NewTimer(delay)
		select {
		case <-ctx.Done():
			timer.Stop()
			return ctx.Err()
		case <-timer.C:
		}
		delay = min(15*time.Second, delay*2)
	}
}

func RunRemote(ctx context.Context, in io.Reader, out io.Writer) error {
	fail := func(code string, err error) error { _ = WriteFrame(out, Frame{Kind: "error", Code: code}); return err }
	envCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	raw, err := exec.CommandContext(envCtx, "systemctl", "--user", "show-environment").Output()
	cancel()
	if err != nil {
		return fail("unavailable", errors.New("cannot read graphical session environment"))
	}
	env, err := DesktopEnvironment(string(raw))
	if err != nil {
		return fail("unavailable", err)
	}
	lock, err := AgentLock(env["XDG_RUNTIME_DIR"])
	if err != nil {
		code := "unavailable"
		if errors.Is(err, errBusy) {
			code = "busy"
		}
		return fail(code, err)
	}
	defer lock.Close()
	// stdin/stdout are files at the CLI boundary; their Close unblocks all IO on EOF/cancellation.
	input, ok := in.(io.ReadCloser)
	if !ok {
		return fmt.Errorf("agent input is not closable")
	}
	output, ok := out.(io.WriteCloser)
	if !ok {
		return fmt.Errorf("agent output is not closable")
	}
	transport := &streamTransport{input, output}
	return RunAgent(ctx, NewWaylandClipboard(sessionSocket(env)), transport)
}
