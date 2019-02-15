---
title: "Go Application Lifecycle"
date: 2019-02-15T13:16:04-07:00
draft: true
# description: >
#     What makes Go's interfaces great, why io.Reader is amazing and implement a
#     new io.Reader
# images:
#   - img/caddyshack.jpg
categories:
  - Programming
tags:
  - Go
---

I like this pattern (having a single root context that manages application
lifecycle). That said, it's one thing to signal to shutdown gracefully and
another to wait and know that everything's actually done.

I wrote [zvelo.io/lifecycle](https://godoc.org/github.com/zvelo/lifecycle) to
manage this (not suggesting we do the same, just offering a method that we
_could_ use).

At the top of `run()`:

```go
ctx := lifecycle.New(
	context.Background(),
	lifecycle.WithTimeout(30*time.Second),
)
```

Then you execute things that it will manage:

```go
lifecycle.Go(ctx, func() {
	// do stuff
})
```

You can also add cleanup tasks that only get run on shutdown:

```go
lifecycle.Defer(ctx, func() {
	// do cleanup stuff
})
```

Then at the end of `run()`:
```go
lifecycle.Wait(ctx)
```

`Wait` blocks until all goroutines started with `Go` complete. It will also
cancel the top level context if the application receives `SIGINT` or `SIGTERM`.
In either case, the `Defer` funcs run to completion as well before `Wait`
returns. The `WithTimeout` at the top is optional and specifies a maximum
amount of time that `Wait` will block. Without it, `Wait` will block
indefinitely until everything completes.

It's easy to plumb through an app too since it's attached to the context. You
can add more `Go` and `Defer` funcs at any time before `Wait` starts to clean
things up.
