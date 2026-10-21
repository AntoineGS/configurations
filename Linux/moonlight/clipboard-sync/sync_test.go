package main

import (
	"bytes"
	"context"
	"net"
	"sync"
	"testing"
	"time"
)

type memoryClipboard struct {
	events  chan Observation
	errors  chan error
	applied chan Selection
	mu      sync.Mutex
	value   Selection
	seq     uint64
}

func newMemoryClipboard(text string) *memoryClipboard {
	return &memoryClipboard{events: make(chan Observation, 16), errors: make(chan error), applied: make(chan Selection, 16), value: Selection{textMIME, []byte(text)}}
}
func (c *memoryClipboard) Watch(context.Context) (<-chan Observation, <-chan error, error) {
	return c.events, c.errors, nil
}
func (c *memoryClipboard) Apply(_ context.Context, s Selection) error {
	c.mu.Lock()
	if c.value.MIME == s.MIME && bytes.Equal(c.value.Data, s.Data) {
		c.mu.Unlock()
		return nil
	}
	c.value = s
	c.mu.Unlock()
	c.applied <- s
	return nil
}
func (c *memoryClipboard) Close() error { return nil }
func (c *memoryClipboard) copy(text string) {
	c.mu.Lock()
	c.seq++
	e := Observation{Seq: c.seq, Selection: Selection{textMIME, []byte(text)}, Present: true}
	c.value = e.Selection
	c.mu.Unlock()
	c.events <- e
}

type pipeTransport struct{ net.Conn }

func (p pipeTransport) Read() (Frame, error) { return ReadFrame(p.Conn) }
func (p pipeTransport) Write(f Frame) error  { return WriteFrame(p.Conn, f) }

func TestSyncInitialClipboardAndNewCopies(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	a, b := net.Pipe()
	defer a.Close()
	defer b.Close()
	local, remote := newMemoryClipboard("local baseline"), newMemoryClipboard("remote baseline")
	done := make(chan error, 2)
	readyA, readyB := make(chan struct{}), make(chan struct{})
	go func() { done <- runSync(ctx, local, pipeTransport{a}, true, func() { close(readyA) }) }()
	go func() { done <- runSync(ctx, remote, pipeTransport{b}, false, func() { close(readyB) }) }()
	for _, ch := range []chan struct{}{readyA, readyB} {
		select {
		case <-ch:
		case err := <-done:
			t.Fatal(err)
		case <-ctx.Done():
			t.Fatal("not ready")
		}
	}
	select {
	case <-local.applied:
		t.Fatal("initial remote copied")
	case <-remote.applied:
		t.Fatal("initial local copied")
	default:
	}
	local.copy("local new\n")
	select {
	case s := <-remote.applied:
		if !bytes.Equal(s.Data, []byte("local new\n")) {
			t.Fatal("wrong local copy")
		}
	case <-ctx.Done():
		t.Fatal("copy timeout")
	}
	remote.copy("remote new\n")
	select {
	case s := <-local.applied:
		if !bytes.Equal(s.Data, []byte("remote new\n")) {
			t.Fatal("wrong remote copy")
		}
	case <-ctx.Done():
		t.Fatal("copy timeout")
	}
	cancel()
	for range 2 {
		select {
		case <-done:
		case <-time.After(time.Second):
			t.Fatal("sync goroutine leaked")
		}
	}
}

func TestSyncAgentKeepsNewerLocalCopy(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	a, b := net.Pipe()
	defer b.Close()
	cb := newMemoryClipboard("initial")
	done := make(chan error, 1)
	ready := make(chan struct{})
	go func() { done <- runSync(ctx, cb, pipeTransport{a}, false, func() { close(ready) }) }()
	peer := pipeTransport{b}
	if f, err := peer.Read(); err != nil || f.Kind != "hello" {
		t.Fatal("missing hello")
	}
	if err := peer.Write(Frame{Kind: "hello"}); err != nil {
		t.Fatal(err)
	}
	if f, err := peer.Read(); err != nil || f.Kind != "ready" {
		t.Fatal("missing ready")
	}
	if err := peer.Write(Frame{Kind: "ready"}); err != nil {
		t.Fatal(err)
	}
	select {
	case <-ready:
	case <-ctx.Done():
		t.Fatal("not ready")
	}
	cb.copy("newer")
	proposal, err := peer.Read()
	if err != nil || proposal.Kind != "proposal" {
		t.Fatal("missing proposal")
	}
	if err := peer.Write(Frame{Kind: "apply", Revision: 1, Seq: 0, MIME: textMIME, Data: []byte("older")}); err != nil {
		t.Fatal(err)
	}
	f, err := peer.Read()
	if err != nil || f.Kind != "ack" {
		t.Fatal("missing processed ack")
	}
	select {
	case <-cb.applied:
		t.Fatal("older update replaced newer local copy")
	default:
	}
	if err := peer.Write(Frame{Kind: "apply", Revision: 2, Seq: proposal.Seq, MIME: textMIME, Data: []byte("accepted")}); err != nil {
		t.Fatal(err)
	}
	if f, err := peer.Read(); err != nil || f.Kind != "ack" {
		t.Fatal("missing apply ack")
	}
	select {
	case s := <-cb.applied:
		if string(s.Data) != "accepted" {
			t.Fatal("wrong final selection")
		}
	case <-ctx.Done():
		t.Fatal("not applied")
	}
	cancel()
	<-done
}
