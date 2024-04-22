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

echo "# user home directory"
ls -la ~
id -a
if [ -f ~/.rpmmacros ] ; then
  cat ~/.rpmmacros
fi
echo

echo "INPUT_SPEC_FILE: ${INPUT_SPEC_FILE}"
if [ -n "${INPUT_SPEC_FILE}" ] ; then
  REPO_SPEC_DIR=$(dirname ${INPUT_SPEC_FILE})
  REPO_SPEC_FILENAME=$(basename ${INPUT_SPEC_FILE})
  RPMBUILDSPECSDIR=$(rpm --eval "%_specdir")
  RPMBUILDSOURCEDIR=$(rpm --eval "%_sourcedir")
  rsync --archive --verbose ${GITHUB_WORKSPACE}/${INPUT_SPEC_FILE} ${RPMBUILDSPECSDIR}/

  if [ -n "${ADDITIONAL_REPOS}" ] ; then
    echo "${ADDITIONAL_REPOS}" | jq -r .[]
    for repo in $(echo "${ADDITIONAL_REPOS}" | jq -r .[]) ; do
      yum-config-manager --enable ${repo}
      ## Correct answer is to test for URL or string
      # yum install -y ${repo}
    done
  fi

  #echo "# rpmlint the SPEC_FILE:"
  #rpmlint ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}
  #retval=$?
  #if [ ${retval} -gt 0 ] ; then
  #  exit ${retval}
  #fi

  echo "# List SPEC_FILE (${REPO_SPEC_FILENAME}) sources: ${INPUT_SPEC_FILE}"
  spectool --sources ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}
  for f in $(spectool --sources ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | egrep -v 'http[s]*://|ftp://' | awk '{print $2}') ; do
    rsync --archive --verbose ${REPO_SPEC_DIR}/../SOURCES/${f} ${RPMBUILDSOURCEDIR}/
  done

  echo "# List SPEC_FILE (${REPO_SPEC_FILENAME}) patches: ${INPUT_SPEC_FILE}"
  spectool --patches ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}
  for p in $(spectool --patches ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | egrep -v 'http[s]*://|ftp://' | awk '{print $2}') ; do
    rsync --archive --verbose ${REPO_SPEC_DIR}/../SOURCES/${p} ${RPMBUILDSOURCEDIR}/
  done

  echo "# Fetch Source and Patches files from URLs"
  spectool --get-files ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}

  echo "# Using yum-builddep from yum-utils to install all the build dependencies for a package"
  yum-builddep -y ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}

  echo "# Build RPM"
  rpmbuild -ba -v ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}
fi

# Use INPUT_<INPUT_NAME> to get the value of an input
GREETING="Hello, $INPUT_WHO_TO_GREET! from $PRETTY_NAME"

# Use workflow commands to do things like set debug messages
echo "::notice file=entrypoint.sh,line=7::$GREETING"

# Write outputs to the $GITHUB_OUTPUT file
echo "greeting=$GREETING" >>"$GITHUB_OUTPUT"

exit 0
