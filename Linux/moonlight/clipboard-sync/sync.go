package main

import (
	"context"
	"errors"
	"fmt"
	"time"
)

type Transport interface {
	Read() (Frame, error)
	Write(Frame) error
	Close() error
}
type readResult struct {
	f   Frame
	err error
}

func RunCoordinator(ctx context.Context, cb Clipboard, t Transport) error {
	return runSync(ctx, cb, t, true, nil)
}
func RunAgent(ctx context.Context, cb Clipboard, t Transport) error {
	return runSync(ctx, cb, t, false, nil)
}

// The loop is the sole owner of protocol state. Clipboard capture and framed IO
// use bounded queues; acceptance order at the coordinator defines conflict order.
func runSync(parent context.Context, cb Clipboard, t Transport, coordinator bool, onReady func()) error {
	ctx, cancel := context.WithCancel(parent)
	defer cancel()
	defer t.Close()
	defer cb.Close()
	events, clipErrors, err := cb.Watch(ctx)
	if err != nil {
		return fmt.Errorf("clipboard unavailable: %w", err)
	}
	incoming := make(chan readResult, 1)
	outgoing := make(chan Frame, 4)
	writeErrors := make(chan error, 1)
	go func() {
		for {
			f, err := t.Read()
			select {
			case incoming <- readResult{f, err}:
			case <-ctx.Done():
				return
			}
			if err != nil {
				return
			}
		}
	}()
	go func() {
		for {
			select {
			case f := <-outgoing:
				if err := t.Write(f); err != nil {
					select {
					case writeErrors <- err:
					case <-ctx.Done():
					}
					return
				}
			case <-ctx.Done():
				return
			}
		}
	}()
	queue := func(f Frame) error {
		select {
		case outgoing <- f:
			return nil
		default:
			return errors.New("clipboard peer backpressure")
		}
	}
	if err = queue(Frame{Kind: "hello"}); err != nil {
		return err
	}
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	lastMessage := time.Now()
	var sentAt time.Time
	var hello, ready, dirty bool
	var revision, waiting, localSeq, remoteSeq uint64
	var latest Selection
	var proposal *Frame
	for {
		// Only one apply can be in flight. Subsequent accepted values coalesce.
		if coordinator && ready && dirty && waiting == 0 {
			if err = queue(Frame{Kind: "apply", Seq: remoteSeq, Revision: revision, MIME: latest.MIME, Data: latest.Data}); err != nil {
				return err
			}
			waiting = revision
			sentAt = time.Now()
			dirty = false
		}
		var send chan Frame
		var pending Frame
		if proposal != nil && ready {
			send = outgoing
			pending = *proposal
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case err := <-clipErrors:
			return err
		case err := <-writeErrors:
			return err
		case send <- pending:
			proposal = nil
		case e := <-events:
			if e.Seq <= localSeq {
				return errors.New("clipboard observation sequence regressed")
			}
			localSeq = e.Seq
			if !ready || !e.Present {
				continue
			}
			if coordinator {
				// A capture queued during Apply may no longer own the local
				// clipboard. Reassert it before making it authoritative remotely.
				if err = cb.Apply(ctx, e.Selection); err != nil {
					return err
				}
				revision++
				latest = e.Selection
				dirty = true
			} else {
				proposal = &Frame{Kind: "proposal", Seq: localSeq, Base: revision, MIME: e.Selection.MIME, Data: e.Selection.Data}
			}
		case result := <-incoming:
			if result.err != nil {
				return result.err
			}
			f := result.f
			lastMessage = time.Now()
			switch f.Kind {
			case "hello":
				if hello {
					return errors.New("duplicate hello")
				}
				hello = true
				if err = queue(Frame{Kind: "ready"}); err != nil {
					return err
				}
			case "ready":
				if !hello || ready {
					return errors.New("unexpected ready")
				}
				ready = true
				if onReady != nil {
					onReady()
				}
			case "ping":
				if err = queue(Frame{Kind: "pong"}); err != nil {
					return err
				}
			case "pong":
			case "error":
				return fmt.Errorf("remote clipboard: %s", f.Code)
			case "proposal":
				if !coordinator || !ready || f.Seq <= remoteSeq || f.Base > revision {
					return errors.New("invalid proposal ordering")
				}
				remoteSeq = f.Seq
				revision++
				latest = Selection{f.MIME, f.Data}
				if err = cb.Apply(ctx, latest); err != nil {
					return err
				}
				dirty = true
			case "apply":
				if coordinator || !ready || f.Revision <= revision || f.Seq > localSeq {
					return errors.New("invalid apply ordering")
				}
				revision = f.Revision
				// A copy not yet accepted by the coordinator must survive an older apply.
				// Ack means processed, including superseded-by-local; its pending proposal
				// will cause a later authoritative revision acknowledging that local Seq.
				if localSeq <= f.Seq {
					if err = cb.Apply(ctx, Selection{f.MIME, f.Data}); err != nil {
						return err
					}
				}
				if err = queue(Frame{Kind: "ack", Seq: localSeq, Revision: revision}); err != nil {
					return err
				}
			case "ack":
				if !coordinator || waiting == 0 || f.Revision != waiting {
					return errors.New("invalid acknowledgement")
				}
				waiting = 0
			default:
				return errFrame
			}
		case now := <-ticker.C:
			if now.Sub(lastMessage) > 15*time.Second || waiting != 0 && now.Sub(sentAt) > 15*time.Second {
				return errors.New("clipboard peer timed out")
			}
			if err = queue(Frame{Kind: "ping"}); err != nil {
				return err
			}
		}
	}
}
