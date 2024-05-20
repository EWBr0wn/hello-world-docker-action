#!/bin/sh -l
set -x
if [ -f /etc/os-release ] ; then
  . /etc/os-release
  echo "::notice file=entrypoint.sh,line=5::${PRETTY_NAME}"
fi

if [ -n "${PRETTY_NAME}" ] ; then
  echo "::group::List env vars"
  env | sort
  echo "::endgroup::"
fi

# Parameterize Verbose, debug_package, and _debugsource_template
#INPUT_SPEC_FILE=contrib/**/*.spec
if [ "${INPUT_VERBOSE}" = 'false' ] || [ -z "${INPUT_VERBOSE}" ] ; then
  # default 'INPUT_VERBOSE=false'
  LONG_VERBOSE=''
  SHORT_VERBOSE=''
else
  LONG_VERBOSE='--verbose'
  SHORT_VERBOSE='-v'
fi
## Check if input variable set for more detailed JSON return set
if [ "${INPUT_OUTPUT_DL_ARTIFACTS}" = 'false' ] || [ -z "${INPUT_OUTPUT_DL_ARTIFACTS}" ] ; then
  # default INPUT_OUTPUT_DL_ARTIFACTS=false
  ## description: 'Add any downloaded artifacts to artifact_array'
  INCLUDEDOWNLOADS='false'
else
  INCLUDEDOWNLOADS='true'
fi
output_array='[]'
if [ "${INPUT_RPM_DEBUGSOURCE_TEMPLATE}" = 'true' ] || [ -z "${INPUT_RPM_DEBUGSOURCE_TEMPLATE}" ] ; then
  # default INPUT_RPM_DEBUGSOURCE_TEMPLATE=true
  LONG_RPM_DS_T=''
else
  LONG_RPM_DS_T='--define "_debugsource_template %{nil}"'
fi
if [ "${INPUT_RPM_DEBUG_PACKAGE}" = 'true' ] || [ -z "${INPUT_RPM_DEBUG_PACKAGE}" ] ; then
  # default 'INPUT_RPM_DEBUG_PACKAGE=true'
  LONG_RPM_DEBUG_PACKAGE=''
else
  LONG_RPM_DEBUG_PACKAGE='--define "debug_package %{nil}"'
fi

echo "::group::user home directory ~/.rpmmacros"
if [ ! -f ~/.rpmmacros ] ; then
  echo '%_topdir /usr/src/rpmbuild' > ~/.rpmmacros
fi
cat ~/.rpmmacros
echo "::endgroup::"

echo "INPUT_SPEC_FILE: ${INPUT_SPEC_FILE}"
if [ -z "${INPUT_SPEC_FILE}" ] ; then
  # no input provided, so set to default
  ## cd to the base of the git checkout, then search for files matching '*.spec'
  ##   output into JSON array to make things easier
  INPUT_SPEC_FILE=$(cd ${GITHUB_WORKSPACE} ; find . -name "*.spec" | head -1 | sed 's#./##')
fi

RPMBUILDSPECSDIR=$(rpm --eval "%_specdir")
RPMBUILDSOURCEDIR=$(rpm --eval "%_sourcedir")
# if the INPUT_SPEC_FILE variable is empty, then 
#   search the checked out directory structure to find *.spec
if [ -n "${INPUT_SPEC_FILE}" ] ; then
  REPO_SPEC_DIR=$(dirname ${INPUT_SPEC_FILE})
  REPO_SPEC_FILENAME=$(basename ${INPUT_SPEC_FILE})

  cp --archive ${LONG_VERBOSE} ${GITHUB_WORKSPACE}/${INPUT_SPEC_FILE} ${RPMBUILDSPECSDIR}/

  if [ -n "${ADDITIONAL_REPOS}" ] ; then
    echo "${ADDITIONAL_REPOS}" | jq -r .[]
    for repo in $(echo "${ADDITIONAL_REPOS}" | jq -r .[]) ; do
      yum-config-manager --enable ${repo}
      ## Correct answer is to test for URL or string
      # yum install -y ${repo}
    done
  fi

  echo "# rpmlint the SPEC_FILE: ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}"
  rpmlint ${LONG_VERBOSE} ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}
  retval=$?
  if [ ${retval} -gt 0 ] ; then
    echo "## retval=${retval} from rpmlint"
  #  exit ${retval}
  fi

  ## Check to see if input variable set for more detailed JSON return set
  
  echo "# List SPEC_FILE (${REPO_SPEC_FILENAME}) sources: ${INPUT_SPEC_FILE}"
  spectool --sources ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}
  # Make list of files that will be copied
  for f in $(spectool --sources ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | egrep -v 'http[s]*://|ftp://' | awk '{print $2}') ; do
    cp --archive ${LONG_VERBOSE} ${GITHUB_WORKSPACE}/${REPO_SPEC_DIR}/../SOURCES/${f} ${RPMBUILDSOURCEDIR}/
  done

  echo "# List SPEC_FILE (${REPO_SPEC_FILENAME}) patches: ${INPUT_SPEC_FILE}"
  spectool --patches ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}
  # Make list of patches that will be copied
  for p in $(spectool --patches ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | egrep -v 'http[s]*://|ftp://' | awk '{print $2}') ; do
    cp --archive ${LONG_VERBOSE} ${GITHUB_WORKSPACE}/${REPO_SPEC_DIR}/../SOURCES/${p} ${RPMBUILDSOURCEDIR}/
  done

  echo "# Fetch Source and Patches files from URLs"
  SRCLISTBEFORE="$(ls -1 ${RPMBUILDSOURCEDIR} | jq -R '[.]' | jq -s -c 'add')"
  spectool --get-files --sourcedir ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}
  if [ "${INCLUDEDOWNLOADS}" = 'true' ] ; then
    SRCLISTAFTER="$(ls -1 ${RPMBUILDSOURCEDIR} | jq -R '[.]' | jq -s -c 'add')"
  else
    SRCLISTAFTER="${SRCLISTBEFORE}"
  fi
  # take every file from SRCLISTBEFORE out of SRCLISTAFTER
  DLSRCLIST="$(jq -n -c --argjson fbefore "${SRCLISTBEFORE}" --argjson fafter "${SRCLISTAFTER}" '$fafter - $fbefore')"
  # make temp file
  SRCEXCLUDETMPFILE=$(mktemp -q /tmp/.source-rsync-exclude.XXXXXX)
  jq -n -c --argjson fbefore "${SRCLISTBEFORE}" --argjson fafter "${SRCLISTAFTER}" '$fbefore - ($fafter - $fbefore)' | \
    jq -r '.[]' | \
    sed 's#^#SOURCES/#' | tee ${SRCEXCLUDETMPFILE}
  if [ "${INCLUDEDOWNLOADS}" = 'true' ] ; then
    RSYNC_DL_SRC_ADDON="--exclude-from=${SRCEXCLUDETMPFILE} ${RPMBUILDSOURCEDIR}"
  else
    RSYNC_DL_SRC_ADDON=''
  fi

  echo "## List files in SOURCES directory"
  ls -l ${RPMBUILDSOURCEDIR}

  echo "# Using yum-builddep from yum-utils to install all the build dependencies for a package"
  yum-builddep -y ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}

  # consider input parameters that control '-v', '-vv', and '--define "debug_package %{nil}"' independently
  echo "# Build RPM"
  rpmbuild -ba ${LONG_RPM_DS_T} ${LONG_RPM_DEBUG_PACKAGE} ${SHORT_VERBOSE} ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}
  retval=$?
  if [ ${retval} -gt 0 ] ; then
    echo "## retval=${retval} from rpmbuild"
  #  exit ${retval}
  fi

  # Command to get Name-Version-Release string from SPEC file
  ## $ rpmspec --define "dist %{nil}" ${LONG_RPM_DEBUG_PACKAGE} ${LONG_RPM_DS_T} --query --queryformat="%{nvr}" ${SPEC}

  echo "# List output RPMs"
  ls -lR $(rpm --eval "%_rpmdir")
  echo "# List expected RPMs"
  rpmspec --query --rpms ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | jq -R -s -c 'split("\n") | map(select(length>0))'
  tmp_rpm_array=$(rpmspec --query --rpms ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | jq -R -s -c 'split("\n") | map(select(length>0))')

  echo "# List output SRPM"
  ls -lR $(rpm --eval "%_srcrpmdir")
  echo "## debug rpmspec"
  tmpstring=$(rpmspec --query --srpm --queryformat="%{arch}" ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME})
  echo "##               - ${tmpstring}"
  echo "# List expected SRPM"
  if [ "${tmpstring}" = "src" ] ; then
    rpmspec --query --srpm ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | jq -R -s -c 'split("\n") | map(select(length>0))'
    tmp_srpm_array="$(rpmspec --query --srpm ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | jq -R -s -c 'split("\n") | map(select(length>0))')"
  else
    ## Potential bug in rpmspec where the Source RPM does not have arch=src
    echo "::notice file=entrypoint.sh,line=136::Mitigating rpmspec bug"
    rpmspec --query --srpm --queryformat="%{name}-%{version}-%{release}.src\n" ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}
    tmp_srpm_array="$(rpmspec --query --srpm --queryformat="%{name}-%{version}-%{release}.src" ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | jq -R -s -c 'split("\n") | map(select(length>0))')"
    ##
  fi

  # If all is good so far, create output directory
  if [ ! -d ${GITHUB_WORKSPACE}/output ] ; then
    mkdir ${LONG_VERBOSE} ${GITHUB_WORKSPACE}/output
  fi

  # Copy output RPMs and if external variable set, copy all files in %_sourcedir as well
  rsync --archive ${LONG_VERBOSE} ${RSYNC_DL_SRC_ADDON} $(rpm --eval "%_rpmdir") $(rpm --eval "%_srcrpmdir") ${GITHUB_WORKSPACE}/output/
  # make temp file
  TMPFILE=$(mktemp -q /tmp/.filearray-egrep.XXXXXX)
  echo ${tmp_rpm_array} | jq -r .[] | awk '{print "/" $1}' | tee ${TMPFILE}
  echo "# finding files"
  find output -type f
  echo "## rpm  - find files matching the following"
  cat ${TMPFILE}
  echo "# make rpm_array"
  find output -type f | egrep -f ${TMPFILE} | jq -R -s -c 'split("\n") | map(select(length>0))'
  rpm_array=$(find output -type f | egrep -f ${TMPFILE} | jq -R -s -c 'split("\n") | map(select(length>0))')
  echo ${tmp_srpm_array} | jq -r .[] | awk '{print "/" $1}' | tee ${TMPFILE}
  echo "## srpm - find files matching the following"
  cat ${TMPFILE}
  echo "# make srpm_array"
  find output -type f | egrep -f ${TMPFILE} | jq -R -s -c 'split("\n") | map(select(length>0))'
  srpm_array=$(find output -type f | egrep -f ${TMPFILE} | jq -R -s -c 'split("\n") | map(select(length>0))')

  # set outputs
  # built_rpm_array:
  #  description: 'JSON array of built RPM files'
  echo "built_rpm_array=${rpm_array}" >> "$GITHUB_OUTPUT"
  # built_srpm_array:
  #  description: 'JSON array of SRPM'
  echo "built_srpm_array=${srpm_array}" >> "$GITHUB_OUTPUT"
  
  # description: 'Content-type for Upload'
  echo "rpm_content_type=application/x-rpm" >> "$GITHUB_OUTPUT"

  # build out the output_array and include ${DLSRCLIST} if set
  ## for each file in ${DLSRCLIST} construct JSON of filename, fullpath, size, MD5, SHA256, modification time, etc.
  echo "artifact_array=${output_array}" >> "$GITHUB_OUTPUT"
fi  # end of if from line 64

# Use INPUT_<INPUT_NAME> to get the value of an input
GREETING="Hello, $INPUT_WHO_TO_GREET! from $PRETTY_NAME"

# Use workflow commands to do things like set debug messages
echo "::notice file=entrypoint.sh,line=204::$GREETING"

# Write outputs to the "$GITHUB_OUTPUT" file
## echo "greeting=$GREETING" >> "$GITHUB_OUTPUT"
## Using tee gleaned from the following:
## https://github.com/FirelightFlagboy/action-gh-release-test/blob/da8751c8d19233021a65a59c448ca26d344b5a89/.github/workflows/release-test.yml#L30
echo "greeting=$GREETING" | tee -a "$GITHUB_OUTPUT"

exit 0
