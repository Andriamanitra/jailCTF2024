  ARGV[0],=Dir["flag-*"]||=[];[*$<]=>[]
# ^^^^^^^^^             ^^^^^      ^^^^
#   (1)    ^^^^^^^^^^^^^ (3)  ^^^^^ (5)
#               (2)            (4)
# Explanation:
# ============
# (1) Adding a filename to ARGV makes ARGF ($<) use that file for reading. The
#     comma is required to unpack the assignment because right side of the
#     assignment is an array.
# (2) Dir["flag-*"] returns array of files matching the glob.
# (3) We must use ||= to prevent step (2) from being a :CALL, with ||= it becomes
#     :OP_ASGN1 instead. (This took way too long to figure out.)
# (4) Splatting ARGF ($<) calls ARGF.readlines thus reading the flag into an array.
# (5) Short-hand pattern matching is a nice way to cause an error message that kindly
#     includes the flag.
