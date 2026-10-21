package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestChooseMIME(t *testing.T) {
	for _, tc := range []struct {
		types []string
		want  string
	}{
		{[]string{"text/plain", "image/png"}, "image/png"},
		{[]string{"UTF8_STRING", "text/plain;charset=utf-8"}, "text/plain;charset=utf-8"},
		{[]string{"text/plain"}, "text/plain"},
		{[]string{"text/uri-list", "application/octet-stream"}, ""},
	} {
		got, _ := ChooseMIME(tc.types)
		if got != tc.want {
			t.Fatalf("MIME choice: %q", got)
		}
	}
}
func TestReadLimited(t *testing.T) {
	if _, err := ReadLimited(strings.NewReader("12345"), 4); err == nil {
		t.Fatal("oversized read")
	}
	b, err := ReadLimited(strings.NewReader(""), 4)
	if err != nil || len(b) != 0 {
		t.Fatal("empty text rejected")
	}
}

func TestClipboardSuppressesRepeatedOwnerEcho(t *testing.T) {
	c := NewWaylandClipboard("unused")
	s := Selection{textMIME, []byte("injected")}
	hash := SelectionHash(s)
	c.pending = &hash
	c.applied = make(chan struct{})
	c.observe(s)
	select {
	case <-c.applied:
	default:
		t.Fatal("injection not acknowledged")
	}
	// Clipboard managers may republish a selection after the original echo.
	c.observe(s)
	select {
	case <-c.events:
		t.Fatal("clipboard manager echo escaped suppression")
	default:
	}
	c.observe(Selection{textMIME, []byte("genuine new copy")})
	select {
	case e := <-c.events:
		if string(e.Selection.Data) != "genuine new copy" {
			t.Fatal("wrong event")
		}
	default:
		t.Fatal("genuine copy lost")
	}
}

func TestClipboardDelayedEchoAndBurst(t *testing.T) {
	c := NewWaylandClipboard("unused")
	s := Selection{textMIME, []byte("injected")}
	hash := SelectionHash(s)
	c.pending, c.applied = &hash, make(chan struct{})
	c.observe(Selection{textMIME, []byte("user copy before echo")})
	c.observe(s)
	e := <-c.events
	if string(e.Selection.Data) != "user copy before echo" {
		t.Fatal("delayed echo overwrote user copy")
	}
	for i := 0; i < 1000; i++ {
		c.observe(Selection{pngMIME, []byte{byte(i >> 8), byte(i)}})
	}
	if len(c.events) != 1 {
		t.Fatal("clipboard burst not coalesced")
	}
	e = <-c.events
	if !bytes.Equal(e.Selection.Data, []byte{3, 231}) {
		t.Fatal("latest copy lost")
	}
}
func TestDesktopEnvironment(t *testing.T) {
	env, err := DesktopEnvironment("OTHER=$(false)\nWAYLAND_DISPLAY=wayland-1\nXDG_RUNTIME_DIR=/run/user/1000\n")
	if err != nil || len(env) != 2 || env["WAYLAND_DISPLAY"] != "wayland-1" {
		t.Fatal("invalid session parse")
	}
	for _, s := range []string{"", "WAYLAND_DISPLAY=a\x00b\nXDG_RUNTIME_DIR=/tmp", "WAYLAND_DISPLAY=x\nXDG_RUNTIME_DIR=relative"} {
		if _, err := DesktopEnvironment(s); err == nil {
			t.Fatal("invalid environment accepted")
		}
	}
}

// A minimal compositor exercises the real Unix socket/FD boundary without touching
// the user's clipboard. Initial text must never become an Observation.
func TestClipboardNativeBaselineAndBinary(t *testing.T) {
	dir := t.TempDir()
	socket := filepath.Join(dir, "wayland-test")
	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: socket, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	ready := make(chan struct{})
	copyNow := make(chan struct{})
	serverErr := make(chan error, 1)
	payload := []byte{137, 80, 78, 71, 0, 255, 10}
	go func() { serverErr <- fakeCompositor(listener, ready, copyNow, payload) }()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	cb := NewWaylandClipboard(socket)
	events, errs, err := cb.Watch(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer cb.Close()
	<-ready
	select {
	case <-events:
		t.Fatal("initial clipboard sent")
	default:
	}
	close(copyNow)
	select {
	case e := <-events:
		if e.Selection.MIME != pngMIME || !bytes.Equal(e.Selection.Data, payload) {
			t.Fatal("image changed")
		}
	case err := <-errs:
		t.Fatal(err)
	case <-ctx.Done():
		t.Fatal("no image event")
	}
	cb.Close()
	if err := <-serverErr; err != nil {
		t.Fatal(err)
	}
}

func fakeCompositor(l *net.UnixListener, ready, copyNow chan struct{}, payload []byte, mode ...string) error {
	c, err := l.AcceptUnix()
	if err != nil {
		return err
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(5 * time.Second))
	// registry request, first sync
	_, _, _, err = readWL(c)
	if err != nil {
		return err
	}
	_, _, data, err := readWL(c)
	if err != nil {
		return err
	}
	syncID := binary.NativeEndian.Uint32(data)
	send := func(id uint32, op uint16, data []byte) error { return writeWL(c, id, op, data, -1) }
	if err = send(2, 0, append(append(wlUint(10), wlString("zwlr_data_control_manager_v1")...), wlUint(2)...)); err != nil {
		return err
	}
	if err = send(2, 0, append(append(wlUint(11), wlString("wl_seat")...), wlUint(7)...)); err != nil {
		return err
	}
	if err = send(syncID, 0, wlUint(1)); err != nil {
		return err
	}
	// bind manager, bind seat, create device, second sync
	for range 3 {
		if _, _, _, err = readWL(c); err != nil {
			return err
		}
	}
	_, _, data, err = readWL(c)
	if err != nil {
		return err
	}
	syncID = binary.NativeEndian.Uint32(data)
	if err = send(6, 0, wlUint(0xff000001)); err != nil {
		return err
	}
	if err = send(0xff000001, 0, wlString("text/plain")); err != nil {
		return err
	}
	if err = send(6, 1, wlUint(0xff000001)); err != nil {
		return err
	}
	if err = send(syncID, 0, wlUint(2)); err != nil {
		return err
	}
	close(ready)
	<-copyNow
	if err = send(6, 0, wlUint(0xff000002)); err != nil {
		return err
	}
	if err = send(0xff000002, 0, wlString("text/plain")); err != nil {
		return err
	}
	if len(mode) == 0 {
		if err = send(0xff000002, 0, wlString("image/png")); err != nil {
			return err
		}
	}
	if err = send(6, 1, wlUint(0xff000002)); err != nil {
		return err
	}
	// Skip destroy requests, receive actual SCM_RIGHTS pipe from offer.receive.
	for {
		data := make([]byte, 4096)
		oob := make([]byte, syscall.CmsgSpace(4))
		_, n, _, _, err := c.ReadMsgUnix(data, oob)
		if err != nil {
			return err
		}
		if n == 0 {
			continue
		}
		msgs, err := syscall.ParseSocketControlMessage(oob[:n])
		if err != nil {
			return err
		}
		for _, m := range msgs {
			fds, err := syscall.ParseUnixRights(&m)
			if err != nil {
				return err
			}
			for _, fd := range fds {
				f := os.NewFile(uintptr(fd), "capture")
				if len(mode) > 0 && (mode[0] == "stalled-owner" || mode[0] == "clear-during-capture") {
					defer f.Close()
					if mode[0] == "clear-during-capture" {
						if _, err = f.Write([]byte("partial")); err != nil {
							return err
						}
					}
					continue
				}
				_, err = f.Write(payload)
				f.Close()
				if err != nil {
					return err
				}
			}
		}
		if len(mode) > 0 {
			if err = send(6, 1, wlUint(0)); err != nil {
				return err
			}
			if err = send(6, 2, nil); err != nil {
				return err
			}
		}
		// Answer lifetime barriers, then remain connected until the adapter closes.
		for {
			id, op, data, err := readWL(c)
			if err != nil {
				if err == io.EOF || strings.Contains(err.Error(), "reset") {
					return nil
				}
				return err
			}
			if id == 1 && op == 0 {
				if err = send(binary.NativeEndian.Uint32(data), 0, wlUint(3)); err != nil {
					return err
				}
			}
		}
	}
}
