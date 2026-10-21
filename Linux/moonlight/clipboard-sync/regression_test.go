package main

import (
	"context"
	"net"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

type racingClipboard struct {
	*memoryClipboard
	once sync.Once
}

func (c *racingClipboard) Apply(ctx context.Context, s Selection) error {
	c.once.Do(func() { c.copy("local A") })
	return c.memoryClipboard.Apply(ctx, s)
}
func TestConcurrentCaptureDuringRemoteApplyConverges(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	a, b := net.Pipe()
	defer b.Close()
	b.SetDeadline(time.Now().Add(3 * time.Second))
	c := &racingClipboard{memoryClipboard: newMemoryClipboard("initial")}
	done := make(chan error, 1)
	go func() { done <- RunCoordinator(ctx, c, pipeTransport{a}) }()
	p := pipeTransport{b}
	p.Read()
	p.Write(Frame{Kind: "hello"})
	p.Read()
	p.Write(Frame{Kind: "ready"})
	p.Write(Frame{Kind: "proposal", Seq: 1, MIME: textMIME, Data: []byte("remote B")})
	for {
		f, err := p.Read()
		if err != nil {
			t.Fatal(err)
		}
		if f.Kind != "apply" {
			continue
		}
		p.Write(Frame{Kind: "ack", Seq: 1, Revision: f.Revision})
		if string(f.Data) != "local A" {
			continue
		}
		c.mu.Lock()
		local := string(c.value.Data)
		c.mu.Unlock()
		if local != string(f.Data) {
			t.Errorf("local and remote authoritative selections diverged")
		}
		break
	}
	cancel()
	<-done
}
func TestDelayedEchoAfterFirstConfirmation(t *testing.T) {
	c := NewWaylandClipboard("unused")
	s := Selection{textMIME, []byte("injected A")}
	h := SelectionHash(s)
	c.pending, c.applied = &h, make(chan struct{})
	c.observe(s)
	c.observe(Selection{textMIME, []byte("genuine B")})
	<-c.events
	c.observe(s)
	select {
	case <-c.events:
		t.Fatal("old injected value became a new copy")
	default:
	}
}
func TestOwnerExitDoesNotTransferEmptyText(t *testing.T) {
	for _, mode := range []string{"owner-exit", "clear-during-capture", "stalled-owner"} {
		t.Run(mode, func(t *testing.T) { testInvalidatedCapture(t, mode) })
	}
}

func testInvalidatedCapture(t *testing.T, mode string) {
	socket := filepath.Join(t.TempDir(), "wayland")
	l, err := net.ListenUnix("unix", &net.UnixAddr{Name: socket, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	ready, copyNow := make(chan struct{}), make(chan struct{})
	serverErr := make(chan error, 1)
	go func() { serverErr <- fakeCompositor(l, ready, copyNow, nil, mode) }()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	c := NewWaylandClipboard(socket)
	events, errs, err := c.Watch(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	<-ready
	close(copyNow)
	select {
	case <-errs:
	case <-ctx.Done():
		t.Fatal("observer did not process source lifetime events")
	}
	select {
	case <-events:
		t.Fatal("dead owner produced transferable empty text")
	default:
	}
	c.Close()
	<-serverErr
}
