package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"syscall"
)

var buildID = "development"

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM, syscall.SIGHUP)
	defer cancel()
	var err error
	switch {
	case len(os.Args) == 2 && os.Args[1] == "version":
		fmt.Println(buildID)
		return
	case len(os.Args) == 2 && os.Args[1] == "agent":
		err = RunRemote(ctx, os.Stdin, os.Stdout)
	case len(os.Args) == 4 && os.Args[1] == "client" && os.Args[2] == "--host":
		err = RunClient(ctx, os.Args[3])
	default:
		fmt.Fprintln(os.Stderr, "usage: moonlight-clipboard client --host HOST | agent | version")
		os.Exit(2)
	}
	if err != nil && !errors.Is(err, context.Canceled) {
		fmt.Fprintln(os.Stderr, "moonlight-clipboard:", err)
		os.Exit(1)
	}
}
