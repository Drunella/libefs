#/!bin/bash

# $1 filename
# $2 startaddress
# $3 number of random bytes


printf "0: %.4x" "$2" | sed -E 's/0: (..)(..)/0: \2\1/' | xxd -r -g0 > "$1"

head -c $3 </dev/urandom >> "$1"

echo "$1, 1"
