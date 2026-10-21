package main

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

func TestAgentLock(t *testing.T) {
	dir := t.TempDir()
	a, err := AgentLock(dir)
	if err != nil {
		t.Fatal(err)
	}
	if b, err := AgentLock(dir); err == nil {
		b.Close()
		t.Fatal("second client accepted")
	}
	if err = a.Close(); err != nil {
		t.Fatal(err)
	}
	b, err := AgentLock(dir)
	if err != nil {
		t.Fatal("lock not released")
	}
	b.Close()
}
func TestCommandSessionCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cmd := exec.CommandContext(ctx, "/usr/bin/sleep", "60")
	cb := newMemoryClipboard("initial")
	done := make(chan error, 1)
	go func() { done <- runCommandSession(ctx, cmd, cb) }()
	// Cancel before or during startup; it must never leave the child alive.
	cancel()
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("child session did not stop")
	}
	if cmd.Process != nil && cmd.ProcessState == nil {
		t.Fatal("child not reaped")
	}
}
func TestRemoteSessionResolution(t *testing.T) {
	runtime := t.TempDir()
	env := map[string]string{"WAYLAND_DISPLAY": "wayland-1", "XDG_RUNTIME_DIR": runtime}
	if got := sessionSocket(env); got != filepath.Join(runtime, "wayland-1") {
		t.Fatal(got)
	}
	env["WAYLAND_DISPLAY"] = "/another/wayland"
	if got := sessionSocket(env); got != "/another/wayland" {
		t.Fatal(got)
	}
}
func TestCommandSessionEarlyExit(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "/bin/sh", "-c", "exit 17")
	if err := runCommandSession(ctx, cmd, newMemoryClipboard("initial")); err == nil {
		t.Fatal("failed child accepted")
	}
	if cmd.ProcessState == nil || cmd.ProcessState.ExitCode() != 17 {
		t.Fatal("child status not collected")
	}
}
func TestAgentLockRejectsSymlink(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(t.TempDir(), "target")
	if err := os.WriteFile(target, []byte("unchanged"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, filepath.Join(dir, "moonlight-clipboard.lock")); err != nil {
		t.Fatal(err)
	}
	if lock, err := AgentLock(dir); err == nil {
		lock.Close()
		t.Fatal("symlink lock accepted")
	}
}
