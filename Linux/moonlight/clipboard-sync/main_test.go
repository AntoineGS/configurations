package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestLauncherChild(t *testing.T) {
	role := os.Getenv("CLIPBOARD_LAUNCHER_CHILD")
	if role == "" {
		return
	}
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGTERM, syscall.SIGUSR1)
	if err := os.WriteFile(filepath.Join(os.Getenv("CLIPBOARD_LAUNCHER_DIR"), role+".pid"), []byte(strconv.Itoa(os.Getpid())), 0600); err != nil {
		os.Exit(99)
	}
	sig := <-signals
	if sig == syscall.SIGUSR1 {
		os.Exit(7)
	}
	os.Exit(0)
}
func TestLauncherReapsClipboardAndKeepsExitStatus(t *testing.T) {
	dir := t.TempDir()
	exe, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	for _, role := range []string{"moonlight", "moonlight-clipboard"} {
		script := fmt.Sprintf("#!/bin/sh\nexport CLIPBOARD_LAUNCHER_CHILD=%s\nexec '%s' -test.run=TestLauncherChild\n", role, exe)
		if err = os.WriteFile(filepath.Join(dir, role), []byte(script), 0700); err != nil {
			t.Fatal(err)
		}
	}
	os.WriteFile(filepath.Join(dir, "getent"), []byte("#!/bin/sh\nprintf '100.127.0.20 STREAM host\\n'\n"), 0700)
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "bash", "../moonlight-office")
	cmd.Env = append(os.Environ(), "PATH="+dir+":"+os.Getenv("PATH"), "CLIPBOARD_LAUNCHER_DIR="+dir)
	if err = cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = cmd.Process.Kill() }()
	waitPID := func(role string) int {
		t.Helper()
		deadline := time.After(3 * time.Second)
		tick := time.NewTicker(5 * time.Millisecond)
		defer tick.Stop()
		for {
			b, e := os.ReadFile(filepath.Join(dir, role+".pid"))
			if e == nil {
				n, e := strconv.Atoi(strings.TrimSpace(string(b)))
				if e != nil {
					t.Fatal(e)
				}
				t.Cleanup(func() { _ = syscall.Kill(n, syscall.SIGKILL) })
				return n
			}
			select {
			case <-deadline:
				t.Fatalf("%s did not launch", role)
			case <-tick.C:
			}
		}
	}
	moonlight := waitPID("moonlight")
	helper := waitPID("moonlight-clipboard")
	syscall.Kill(moonlight, syscall.SIGUSR1)
	err = cmd.Wait()
	if err == nil || cmd.ProcessState.ExitCode() != 7 {
		t.Fatalf("lost Moonlight status: %v", err)
	}
	if err = syscall.Kill(helper, 0); err == nil {
		t.Fatal("clipboard helper survived launcher")
	}
}
