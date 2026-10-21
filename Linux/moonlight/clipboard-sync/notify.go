package main

import (
	"context"
	"os/exec"
	"sync"
	"time"
)

var notificationGate struct {
	sync.Mutex
	last time.Time
}

func notify(message string) {
	notificationGate.Lock()
	if time.Since(notificationGate.last) < 30*time.Second {
		notificationGate.Unlock()
		return
	}
	notificationGate.last = time.Now()
	notificationGate.Unlock()
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = exec.CommandContext(ctx, "notify-send", "Office PC clipboard", message).Run()
	}()
}
