#!/bin/sh -l

if [ -f /etc/os-release ] ; then
  . /etc/os-release
fi

echo "# List env vars"
env | sort
echo

echo "# List recursively /usr/src"
ls -lhR /usr/src
echo

echo "# List GITHUB_WORKSPACE: ${GITHUB_WORKSPACE}"
ls -lhR ${GITHUB_WORKSPACE}
echo

# Use INPUT_<INPUT_NAME> to get the value of an input
GREETING="Hello, $INPUT_WHO_TO_GREET! from $PRETTY_NAME"

# Use workflow commands to do things like set debug messages
echo "::notice file=entrypoint.sh,line=7::$GREETING"

# Write outputs to the $GITHUB_OUTPUT file
echo "greeting=$GREETING" >>"$GITHUB_OUTPUT"

exit 0
