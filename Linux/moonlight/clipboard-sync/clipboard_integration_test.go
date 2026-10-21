package main

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"
)

// Explicitly opt into a separate compositor, never the user's live clipboard.
func TestClipboardIsolatedCompositor(t *testing.T) {
	socket := os.Getenv("CLIPBOARD_TEST_SOCKET")
	if socket == "" {
		t.Skip("set CLIPBOARD_TEST_SOCKET to an isolated compositor")
	}
	if !strings.HasPrefix(socket, "/tmp/opencode/cb/") {
		t.Fatal("refusing non-test compositor")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	copyValue := func(mime string, data []byte) {
		t.Helper()
		cmd := exec.CommandContext(ctx, "/usr/bin/wl-copy", "--type", mime)
		cmd.Env = append(os.Environ(), "WAYLAND_DISPLAY="+socket)
		cmd.Stdin = bytes.NewReader(data)
		if err := cmd.Run(); err != nil {
			t.Fatal(err)
		}
	}
	copyValue(textMIME, []byte("initial"))
	cb := NewWaylandClipboard(socket)
	events, errs, err := cb.Watch(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer cb.Close()
	select {
	case <-events:
		t.Fatal("startup copied")
	default:
	}
	for _, s := range []Selection{{textMIME, []byte("new text\n")}, {pngMIME, []byte{137, 80, 78, 71, 0, 255}}, {textMIME, []byte{}}} {
		copyValue(s.MIME, s.Data)
		select {
		case got := <-events:
			if got.Selection.MIME != s.MIME || !bytes.Equal(got.Selection.Data, s.Data) {
				t.Fatal("selection mismatch")
			}
		case err := <-errs:
			t.Fatal(err)
		case <-ctx.Done():
			t.Fatal("event timeout")
		}
	}
	// Apply returns only after its watcher echo is consumed; no sleeps needed.
	if err = cb.Apply(ctx, Selection{textMIME, []byte("injected")}); err != nil {
		t.Fatal(err)
	}
	select {
	case <-events:
		t.Fatal("injected clipboard echoed")
	default:
	}
	cb.Close()
	cmd := exec.CommandContext(ctx, "/usr/bin/wl-paste", "--no-newline")
	cmd.Env = append(os.Environ(), "WAYLAND_DISPLAY="+socket)
	data, err := cmd.Output()
	if err != nil || string(data) != "injected" {
		t.Fatal("clipboard lost after helper closes")
	}
}
