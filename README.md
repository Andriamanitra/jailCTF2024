# jailCTF2024

I participated in the event as a member of the winning [`chr(sum(range(ord(min(str(not()))))))`](https://ctf.pyjail.club/profile/e8adae37-6507-479b-b3bd-4e0ef3ac6477)
team which was formed by members of the code.golf Discord.

Although I spent time on other challenges too my main contributions were capturing the
`ruby-on-jails` flag (which we were the only team to do successfully) and the `MMM`
flag which was only captured by one other team.

## ruby-on-jails

The key to solving ruby-on-jails was to figure out all the different ways you can call
methods without explicitly calling methods as the challenge code didn't permit any of these:
```rb
$banned_opcodes = [ :CALL, :FCALL, :OPCALL, :QCALL, :VCALL, :DXSTR, :XSTR, :ALIAS, :VALIAS ]
```

I was already aware of many different ways to trigger method calls as I have done quite
a bit of creative Ruby coding on [CodinGame](https://www.codingame.com/servlet/urlinvite?u=3893564)
and [code.golf](https://code.golf/). I immediately realized you can use spread operator
on `ARGF` to read lines from files specified in `ARGV`. It just wasn't immediately obvious
how to modify `ARGV` and especially find the right filename, as it included randomized hexadecimal
digits.

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
result of the read, which I eventually figured out I could do by causing an error that
includes the contents of the file in the message (simplest way to do that is unsuccessful
pattern match with `=> []`). The part that took very long time to figure out was figuring
out a way to find the filename (as the actual name was randomized by using `/dev/urandom`).

Interesting side note: If we were able to call [`IO.readlines("|ls")`](https://ruby-doc.org/3.3.5/IO.html#method-c-readlines)
that would have already given us arbitrary code execution. Unfortunately (for some reason I
still do not quite understand, please let me know if you know!) the behavior is different when
`#readlines` is called with `super("|ls")` from a subclass, and using the pipe character does
**not** do a system call.

After a while a team mate of mine (@Natanaelel) managed to shorten the partial solution to this:
```rb
ARGV[0]="flag.txt";[*$<]=>[]
```

It all finally clicked when another team mate (@MeWhenI) posted this (non-working) version
in the team chat where we had been discussing the problem:
```rb
ARGV[0],=Dir["/srv/app/flag-*.txt"];[*$<]=>[]
```
I had played around with `Dir[]` already the previous day inside my `K` class but seeing
it in this context made it click. The reason we were not able to use `Dir[]` is because it
was lacking an assignment! I could just add `||=[]` to change the parser to think of it as
a different type (`:OP_ASGN1`).
