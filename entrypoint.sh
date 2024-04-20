#!/bin/sh -l

if [ -f /etc/os-release ] ; then
  . /etc/os-release
fi

echo "# List env vars" && \
  env | sort && \
  echo

echo "# List recursively /usr/src" && \
  ls -lhR /usr/src && \
  echo

echo "# List GITHUB_WORKSPACE: ${GITHUB_WORKSPACE}" && \
  ls -lhR ${GITHUB_WORKSPACE} && \
  echo

if [ -n "${INPUT_SPEC_FILE}" ] ; then
  REPO_SPEC_DIR=$(dirname ${INPUT_SPEC_FILE}) && \
    REPO_SPEC_FILENAME=$(basename ${INPUT_SPEC_FILE}) && \
    cp --archive --verbose ${GITHUB_WORKSPACE}/${INPUT_SPEC_FILE} /usr/src/rpmbuild/SPECS/
  echo "# List SPEC_FILE (${REPO_SPEC_FILENAME}) patches: ${INPUT_SPEC_FILE}" && \
    spectool --sources /usr/src/rpmbuild/SPECS/${REPO_SPEC_FILENAME}
  echo "# List SPEC_FILE (${REPO_SPEC_FILENAME}) sources: ${INPUT_SPEC_FILE}" && \
    spectool --patches /usr/src/rpmbuild/SPECS/${REPO_SPEC_FILENAME}
fi

# Use INPUT_<INPUT_NAME> to get the value of an input
GREETING="Hello, $INPUT_WHO_TO_GREET! from $PRETTY_NAME"

# Use workflow commands to do things like set debug messages
echo "::notice file=entrypoint.sh,line=7::$GREETING"

# Write outputs to the $GITHUB_OUTPUT file
echo "greeting=$GREETING" >>"$GITHUB_OUTPUT"

exit 0
