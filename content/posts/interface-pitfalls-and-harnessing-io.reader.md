---
title: Interface Pitfalls and Harnessing `io.Reader`
date: 2016-10-20T00:00:00-07:00
draft: false
description: >
    Learn what makes Go’s interfaces great, see why io.Reader is amazing and
    implement a new io.Reader
images:
  - img/caddyshack.jpg
categories:
  - Programming
tags:
  - Go
---

When Go was first announced I remember looking over the list of its key
features and feeling astonished that a new language would omit the classes and
inheritance that I had come to depend on so heavily. My interest faded quickly.

Fast forward a few years and our team has fully embraced Go for its speed,
tooling, standard library, concurrency support and all the other things we know
and love about Go. If you’re interested in learning more about how we use Go at
zvelo, we’ve recently [published a blog post](https://zvelo.com/zvelo-on-the-go/).

The concept of interfaces, while certainly not new to us, seemed more like an
afterthought in our embrace of the language. We had used interfaces in C++, and
they were useful but tedious. Despite hearing so many great things about
implicitly satisfied interfaces, it still took us quite a while to really
internalize what the implications of this simple concept were.

Let’s walk through the process that a newcomer to Go might follow in developing
a simple text processor that replaces instances of _“hodor”_ with _“hold the door”_.
We will start with a naïve implementation and refactor it over several steps.

---

## Naïve Implementation

```go
func process(text string) string {
	return regexp.MustCompile(`hodor`).
		ReplaceAllString(text, `hold the door`)
}
```

<center><sup><https://play.golang.org/p/wQ8UUjNi7u></sup></center>

```
string length: 130B
BenchmarkNaive-8  200000  13003 ns/op  41985 B/op  45 allocs/op

string length: 130000B
BenchmarkNaive-8  200  6584315 ns/op  1494456 B/op  10063 allocs/op
```

Let’s ignore for the duration of the exercise the simplicity of the
function — it simply represents anything that has to modify data. There are
several obvious problems. First of all, the most glaring issue is that the
regular expression is being compiled every time _process_ is executed.
Additionally, while there is no risk here (since the regex is fine), if the
regular expression were to fail compilation (if, say, it was loaded
dynamically), it would cause the application to panic during runtime. This would
be unacceptable for production systems, and proper error handling should have
been used instead (with `regexp.Compile`), but I digress.

---

## Precompiled Regular Expressions

```go
var re = regexp.MustCompile(`hodor`)

func process(text string) string {
	return re.ReplaceAllString(text, `hold the door`)
}
```

<center><sup><https://play.golang.org/p/D4mx4gHpoz></sup></center>

We keep using `regexp.MustCompile`, but because compilation occurs during
initialization, any errors in the regex are exposed immediately on application
startup. Benchmarking the updated function yields significantly better
performance for small strings, but as strings get larger the benefit approaches
zero.

```
string length: 130B
BenchmarkCRegex-8  300000  3724 ns/op  880 B/op  16 allocs/op

string length: 130000B
BenchmarkCRegex-8  200  5937989 ns/op  1492260 B/op  10032 allocs/op
```

---

## Avoiding Regular Expressions

Regular expressions are excellent tools that have many valid uses, but are often
abused when simple text processing will suffice.

```go
func process(text string) string {
	return strings.Replace(text, "hodor", "hold the door", -1)
}
```

<center><sup><https://play.golang.org/p/JB-ozcVTrt></sup></center>

```
string length: 130B
BenchmarkAvoidRegex-8  2000000  689 ns/op  448 B/op  2 allocs/op

string length: 130000B
BenchmarkAvoidRegex-8  3000  527535 ns/op  425999 B/op  3 allocs/op
```

By using `strings.Replace` instead of a regular expression, we improve the
performance by an order of magnitude for both short and long strings. We also
minimize the number of memory allocations. Keep an eye on the B/op though, it
scales with string size and that may become an issue for very large strings.
Also, what if we want to operate on large files or even a network socket?

---

## Using `io.Reader`

Let’s see if we can make this a bit more generic by using `io.Reader` instead of
`string`. We’ve seen `io.Reader` used with things like `os.File` and figure that we
can make that work somehow. But how do we return the processed data to the
caller? Let’s just return another `io.Reader`.

```go
func process(r io.Reader) (io.Reader, error) {
	data, err := ioutil.ReadAll(r)
	if err != nil {
		return nil, err
	}
	return strings.NewReader(strings.Replace(string(data), "hodor", "hold the door", -1)), nil
}
```

<center><sup><https://play.golang.org/p/tZSjg7van_><sup></center>

```
string length: 130B
BenchmarkBadIface-8  1000000  2111 ns/op  4720 B/op  8 allocs/op

string length: 130000B
BenchmarkBadIface-8  2000  675796 ns/op  1339467 B/op  24 allocs/op
```

Great! Now we are using interfaces, we’re golden right? Well… not so much. We
aren’t using less memory since we are using `ioutil.ReadAll` (which is almost
always incorrect and only works with readers that return `io.EOF`). Further, we
are just wastefully turning the result into an `io.Reader` from the string. To add
insult to injury, our performance has dropped significantly across all metrics
too.

---

## Streaming Data

It now occurs to us that if we streamed the data, byte by byte, we can avoid
the large memory allocations. This does introduce a new knob that will affect
processing performance. We will have to choose how much data to buffer at a
time before running `Replace`. The larger the chunk size, the higher the B/op.
The smaller the chunk size, the greater the number of times data has to be
copied. There is no right answer for every situation.

It should be noted that there is a bit of a bug in this implementation in that
the chunk could read until the middle of a _hodor_ and it wouldn’t get replaced
properly. Since this code is for demonstration only, fixing it is an exercise
left to the reader.

```go
// DefaultChunkSize is the default amount of data read from an io.Reader
const DefaultChunkSize = 1024 * 16

// Process starts to stream data
func Process(r io.Reader) (io.Reader, error) {
	var buf, rbuf, result bytes.Buffer

	for {
		_, err := io.CopyN(&buf, r, DefaultChunkSize)
		if err != nil && err != io.EOF {
			return nil, err
		}

		if rerr := Replace(buf.Bytes(), []byte("hodor"), []byte("hold the door"), -1, &rbuf); rerr != nil {
			return nil, rerr
		}

		buf.Reset()

		if _, werr := result.Write(rbuf.Bytes()); werr != nil {
			return nil, werr
		}

		if err == io.EOF {
			return &result, nil
		}
	}
}
```

<center><sup><https://play.golang.org/p/NWBTaYI6Fe></sup></center>

```
string length: 130B, chunk size: 16384B
BenchmarkBadStream-8  500000  2886 ns/op  4912 B/op  10 allocs/op

string length: 130000B, chunk size: 16384B
BenchmarkBadStream-8  2000  884182 ns/op  1314940 B/op  35 allocs/op
```

This is definitely a step in the right direction as we are truly streaming the
data now. However, because we are also managing the output buffer, we still
require more memory and allocations than necessary. Don’t worry about the
performance loss, things are about to get much better.

---

## A Quick Side Note about Replace

Astute readers will see the as yet undefined `Replace` in the above code. In
effect, it is only `bytes.Replace`.

```go
// Replace reimplements bytes.Replace in a way that can reuse the buffer
func Replace(s, old, new []byte, n int, buf *bytes.Buffer) error {
	m := 0

	if n != 0 {
		// Compute number of replacements.
		m = bytes.Count(s, old)
	}

	if buf == nil {
		buf = &bytes.Buffer{}
	}

	buf.Reset()

	if m == 0 {
		// Just return a copy.
		_, err := buf.Write(s)
		return err
	}

	if n < 0 || m < n {
		n = m
	}

	// Apply replacements to buffer.
	buf.Grow(len(s) + n*(len(new)-len(old)))

	start := 0
	for i := 0; i < n; i++ {
		j := start

		if len(old) == 0 {
			if i > 0 {
				_, wid := utf8.DecodeRune(s[start:])
				j += wid
			}
		} else {
			j += bytes.Index(s[start:], old)
		}

		if _, err := buf.Write(s[start:j]); err != nil {
			return err
		}

		if _, err := buf.Write(new); err != nil {
			return err
		}

		start = j + len(old)
	}

	_, err := buf.Write(s[start:])
	return err
}
```

<center><sup><https://golang.org/pkg/bytes/#Replace></sup></center>

The difference between `Replace` and `bytes.Replace` is that `Replace` is
passed a `bytes.Buffer`. The benefit of this is not fully realized yet, but it
allows an already allocated buffer to be used instead of requiring new
allocations every time it is called. This is the same strategy that
[`io.CopyBuffer`](https://golang.org/pkg/io/#CopyBuffer) uses. Since there is
no `bytes.ReplaceBuffer` it had to be copied and modified.

---

## Pushing Memory Allocation to the Caller

Let’s look at one more possibility for a `Process` func. Rather than handling the
memory allocation ourselves, with `bytes.Buffer`, let’s let the caller decide how
to handle memory by allowing a passed in `io.Writer`.

```go
func Process(w io.Writer, r io.Reader) error {
	var buf, rbuf bytes.Buffer
	for {
		_, err := io.CopyN(&buf, r, DefaultChunkSize)
		if err != nil && err != io.EOF {
			return err
		}

		if rerr := Replace(buf.Bytes(), []byte("hodor"), []byte("hold the door"), -1, &rbuf); rerr != nil {
			return rerr
		}

		buf.Reset()

		if _, werr := w.Write(rbuf.Bytes()); werr != nil {
			return werr
		}

		if err == io.EOF {
			return nil
		}
	}
}
```

<center><sup><https://play.golang.org/p/Fkq2ObxIuy></sup></center>

```
string length: 130B, chunk size: 16384B
BenchmarkMalloc-8  1000000  1897 ns/op  2528 B/op  6 allocs/op

string length: 130000B, chunk size: 16384B
BenchmarkMalloc-8  2000  624815 ns/op  92387 B/op  17 allocs/op
```

This is certainly cleaner, and is a bit more performant and memory conscious.
What if there was a way for us to prevent the need for _any_ write buffer?

---

## Implementing our own `io.Reader`

By writing a `Processor` that implements the `io.Reader` interface itself, we can
essentially create a pipeline for data to flow while minimizing data
allocations. As an `io.Reader` our `Processor` is usable by any number of packages
in the standard library and third party packages.

```go
// Processor implements an io.Reader
type Processor struct {
	Src       io.Reader
	Old, New  []byte
	ChunkSize int
	buf, rbuf bytes.Buffer
}

// Reset the processor
func (m *Processor) Reset(src io.Reader) {
	m.Src = src
	m.buf.Reset()
}

func (m *Processor) Read(p []byte) (int, error) {
	if m.ChunkSize == 0 {
		m.ChunkSize = DefaultChunkSize
	}

	// first flush any buffered data to p
	n, err := m.buf.Read(p)
	if n == len(p) || (err != nil && err != io.EOF) {
		return n, err
	}

	// m.buf must be empty now
	_, err = io.CopyN(&m.buf, m.Src, int64(m.ChunkSize))
	if err != nil && err != io.EOF {
		return n, err
	}

	rerr := Replace(m.buf.Bytes(), m.Old, m.New, -1, &m.rbuf)
	m.buf.Reset()

	if rerr != nil {
		return n, rerr
	}

	copied, rerr := m.rbuf.Read(p[n:])
	n += copied
	if rerr != nil && rerr != io.EOF {
		return n, rerr
	}

	// copy anything not put in p, back to the buffer
	if _, rerr := m.buf.ReadFrom(&m.rbuf); rerr != nil {
		return n, rerr
	}

	return n, err
}
```

<center><sup><https://play.golang.org/p/SY-W32GJ3L></sup></center>

```
# STANDARD CHUNK SIZE

string length: 130B, chunk size: 16384B
BenchmarkProcReadAll-8  2000000   899 ns/op  32 B/op  1 allocs/op
BenchmarkProcRead-8     1000000  1056 ns/op  32 B/op  1 allocs/op

string length: 130000B, chunk size: 16384B
BenchmarkProcReadAll-8   3000  674009 ns/op  256 B/op  8 allocs/op
BenchmarkProcRead-8     30000   54461 ns/op   21 B/op  0 allocs/op

# LARGER CHUNK SIZE

string length: 130B, chunk size: 131072B
BenchmarkProcReadAll-8  2000000  909 ns/op  32 B/op  1 allocs/op
BenchmarkProcRead-8     2000000  985 ns/op  32 B/op  1 allocs/op

string length: 130000B, chunk size: 131072B
BenchmarkProcReadAll-8  2000  642961 ns/op  32 B/op  1 allocs/op
BenchmarkProcRead-8     2000  634125 ns/op  32 B/op  1 allocs/op

# SMALLER CHUNK SIZE

string length: 130B, chunk size: 1024B
BenchmarkProcReadAll-8  2000000  889 ns/op  32 B/op  1 allocs/op
BenchmarkProcRead-8     2000000  910 ns/op  32 B/op  1 allocs/op

string length: 130000B, chunk size: 1024B
BenchmarkProcReadAll-8  2000  623435 ns/op  4065 B/op  127 allocs/op
BenchmarkProcRead-8   500000    3140 ns/op    19 B/op    0 allocs/op
```

This is what we were looking for. It is nearly as performant as the
`strings.Replace` version but uses a fraction of the memory and causes very
little garbage collector thrashing.

The `ReadAll` metrics consider reading all of the `io.Reader` as a single
operation, whereas the `Read` metrics consider one `r.Read` function as a single
operation.

It now becomes much clearer how different chunk sizes affect things. Smaller
chunks result in more allocations, but much faster individual `r.Read`
operations. Larger chunks work much like `strings.Replace` since they are getting
most of the data at once and their performance and memory requirements (though
not allocations) approach it as well.

One thing to note is that the B/op metric is a bit deceiving since we are
reusing the buffers so heavily. They indicate an average across many calls. The
first few calls will do all of the allocations and then all subsequent ones can
reuse them without requiring new allocations. The actual memory used by each
call corresponds more closely with the chunk size.

For reference, here is the same test as the previous one, but using
`bytes.Replace` instead of our buffered `Replace`.

```
string length: 130B, chunk size: 16384B
BenchmarkProcReadAll-8 2000000 784 ns/op 256 B/op 2 allocs/op
BenchmarkProcRead-8    2000000 775 ns/op 256 B/op 2 allocs/op

string length: 130000B, chunk size: 16384B
BenchmarkProcReadAll-8  3000 482607 ns/op 224007 B/op 16 allocs/op
BenchmarkProcRead-8    20000  66704 ns/op  28000 B/op  2 allocs/op
```

The primary difference is that the B/op metric is 3 orders of magnitude larger
for long strings.

If you are more of a visual learner, [here is the data in a few
charts](http://www.charted.co/c/f949a56), and [here is its source
data](https://docs.google.com/spreadsheets/d/1Ftxpzfe2dgW4wQiysnMp8dyHspUq-IA-NtDTuI-oNtw/edit?usp=sharing).

---

## Conclusion

I’ve attempted to illustrate the learning process that someone coming from
languages like Perl or Python might follow. Starting with regular expressions
and ending with implementing an `io.Reader`, is certainly a possible, if
unlikely, progression. While for this simple example `strings.Replace` certainly
would have sufficed, more complicated algorithms might justify the additional
complexity.

Remember, here, as always, write clean, maintainable code first, test it, then
measure its performance. Only then optimize the parts where the performance is
required.
