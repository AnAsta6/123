#!/bin/sh
# Copyright 2000-2024 JetBrains s.r.o. and contributors. Use of this source code is governed by the Apache 2.0 license.

# ---------------------------------------------------------------------
# PyCharm startup script.
# ---------------------------------------------------------------------

message()
{
  TITLE="Cannot start PyCharm"
  if [ -n "$(command -v zenity)" ]; then
    zenity --error --title="$TITLE" --text="$1" --no-wrap
  elif [ -n "$(command -v kdialog)" ]; then
    kdialog --error "$1" --title "$TITLE"
  elif [ -n "$(command -v notify-send)" ]; then
    notify-send "ERROR: $TITLE" "$1"
  elif [ -n "$(command -v xmessage)" ]; then
    xmessage -center "ERROR: $TITLE: $1"
  else
    printf "ERROR: %s\n%s\n" "$TITLE" "$1"
  fi
}

if [ -z "$(command -v uname)" ] || [ -z "$(command -v realpath)" ] || [ -z "$(command -v dirname)" ] || [ -z "$(command -v cat)" ] || \
   [ -z "$(command -v grep)" ]; then
  TOOLS_MSG="Required tools are missing:"
  for tool in uname realpath grep dirname cat ; do
     test -z "$(command -v $tool)" && TOOLS_MSG="$TOOLS_MSG $tool"
  done
  message "$TOOLS_MSG (SHELL=$SHELL PATH=$PATH)"
  exit 1
fi

# shellcheck disable=SC2034
GREP_OPTIONS=''
OS_TYPE=$(uname -s)
OS_ARCH=$(uname -m)

# ---------------------------------------------------------------------
# Ensure $IDE_HOME points to the directory where the IDE is installed.
# ---------------------------------------------------------------------
IDE_BIN_HOME=$(dirname "$(realpath "$0")")
IDE_HOME=$(dirname "${IDE_BIN_HOME}")
CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"

# ---------------------------------------------------------------------
# Locate a JRE installation directory command -v will be used to run the IDE.
# Try (in order): $PYCHARM_JDK, .../pycharm.jdk, .../jbr, $JDK_HOME, $JAVA_HOME, "java" in $PATH.
# ---------------------------------------------------------------------
JRE=""

# shellcheck disable=SC2154
if [ -n "$PYCHARM_JDK" ] && [ -x "$PYCHARM_JDK/bin/java" ]; then
  JRE="$PYCHARM_JDK"
fi

if [ -z "$JRE" ] && [ -s "${CONFIG_HOME}/JetBrains/PyCharm2025.2/pycharm.jdk" ]; then
  USER_JRE=$(cat "${CONFIG_HOME}/JetBrains/PyCharm2025.2/pycharm.jdk")
  if [ -x "$USER_JRE/bin/java" ]; then
    JRE="$USER_JRE"
  fi
fi

if [ -z "$JRE" ] && [ "$OS_TYPE" = "Linux" ] && [ -f "$IDE_HOME/jbr/release" ]; then
  JBR_ARCH="OS_ARCH=\"$OS_ARCH\""
  if grep -q -e "$JBR_ARCH" "$IDE_HOME/jbr/release" ; then
    JRE="$IDE_HOME/jbr"
  fi
fi

# shellcheck disable=SC2153
if [ -z "$JRE" ]; then
  if [ -n "$JDK_HOME" ] && [ -x "$JDK_HOME/bin/java" ]; then
    JRE="$JDK_HOME"
  elif [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    JRE="$JAVA_HOME"
  fi
fi

if [ -z "$JRE" ]; then
  JAVA_BIN=$(command -v java)
else
  JAVA_BIN="$JRE/bin/java"
fi

if [ -z "$JAVA_BIN" ] || [ ! -x "$JAVA_BIN" ]; then
  message "No JRE found. Please make sure \$PYCHARM_JDK, \$JDK_HOME, or \$JAVA_HOME point to valid JRE installation."
  exit 1
fi

# ---------------------------------------------------------------------
# Collect JVM options and IDE properties.
# ---------------------------------------------------------------------
IDE_PROPERTIES_PROPERTY=""
# shellcheck disable=SC2154
if [ -n "$PYCHARM_PROPERTIES" ]; then
  IDE_PROPERTIES_PROPERTY="-Didea.properties.file=$PYCHARM_PROPERTIES"
fi

# shellcheck disable=SC2034
IDE_CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/JetBrains/PyCharm2025.2"

# <IDE_HOME>/bin/[<os>/]<bin_name>.vmoptions ...
VM_OPTIONS_FILE=""
if [ -r "${IDE_BIN_HOME}/pycharm64.vmoptions" ]; then
  VM_OPTIONS_FILE="${IDE_BIN_HOME}/pycharm64.vmoptions"
else
  test "${OS_TYPE}" = "Darwin" && OS_SPECIFIC="mac" || OS_SPECIFIC="linux"
  if [ -r "${IDE_BIN_HOME}/${OS_SPECIFIC}/pycharm64.vmoptions" ]; then
    VM_OPTIONS_FILE="${IDE_BIN_HOME}/${OS_SPECIFIC}/pycharm64.vmoptions"
  fi
fi

# ... [+ $<IDE_NAME>_VM_OPTIONS || <IDE_HOME>.vmoptions (Toolbox) || <config_directory>/<bin_name>.vmoptions]
USER_VM_OPTIONS_FILE=""
if [ -n "$PYCHARM_VM_OPTIONS" ] && [ -r "$PYCHARM_VM_OPTIONS" ]; then
  USER_VM_OPTIONS_FILE="$PYCHARM_VM_OPTIONS"
elif [ -r "${IDE_HOME}.vmoptions" ]; then
  USER_VM_OPTIONS_FILE="${IDE_HOME}.vmoptions"
elif [ -r "${CONFIG_HOME}/JetBrains/PyCharm2025.2/pycharm64.vmoptions" ]; then
  USER_VM_OPTIONS_FILE="${CONFIG_HOME}/JetBrains/PyCharm2025.2/pycharm64.vmoptions"
fi

VM_OPTIONS=""
if [ -z "$VM_OPTIONS_FILE" ] && [ -z "$USER_VM_OPTIONS_FILE" ]; then
  message "Cannot find a VM options file"
elif [ -z "$USER_VM_OPTIONS_FILE" ]; then
  VM_OPTIONS=$(grep -E -v -e "^#.*" "$VM_OPTIONS_FILE")
elif [ -z "$VM_OPTIONS_FILE" ]; then
  VM_OPTIONS=$(grep -E -v -e "^#.*" "$USER_VM_OPTIONS_FILE")
else
  VM_FILTER=""
  if grep -E -q -e "-XX:\+.*GC" "$USER_VM_OPTIONS_FILE" ; then
    VM_FILTER="-XX:\+.*GC|"
  fi
  if grep -E -q -e "-XX:InitialRAMPercentage=" "$USER_VM_OPTIONS_FILE" ; then
    VM_FILTER="${VM_FILTER}-Xms|"
  fi
  if grep -E -q -e "-XX:(Max|Min)RAMPercentage=" "$USER_VM_OPTIONS_FILE" ; then
    VM_FILTER="${VM_FILTER}-Xmx|"
  fi
  if [ -z "$VM_FILTER" ]; then
    VM_OPTIONS=$(cat "$VM_OPTIONS_FILE" "$USER_VM_OPTIONS_FILE" 2> /dev/null | grep -E -v -e "^#.*")
  else
    VM_OPTIONS=$({ grep -E -v -e "(${VM_FILTER%'|'})" "$VM_OPTIONS_FILE"; cat "$USER_VM_OPTIONS_FILE"; } 2> /dev/null | grep -E -v -e "^#.*")
  fi
fi

CLASS_PATH="$IDE_HOME/lib/platform-loader.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/util-8.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/app-client.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/util.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/product.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/app.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/annotations.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/bouncy-castle.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/eclipse.lsp4j.debug.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/eclipse.lsp4j.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/eclipse.lsp4j.jsonrpc.debug.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/eclipse.lsp4j.jsonrpc.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/external-system-rt.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/externalProcess-rt.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/forms_rt.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/groovy.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/javax.activation.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/javax.annotation-api.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/jaxb-api.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/jaxb-runtime.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/jps-model.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/jsch-agent.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/kotlinx-coroutines-slf4j-1.10.1-intellij.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/lib-client.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/lib.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/opentelemetry.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/product-client.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/protobuf.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/rd.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/rhino.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/stats.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/trove.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/util_rt.jar"

# ---------------------------------------------------------------------
# Run the IDE.
# ---------------------------------------------------------------------
IFS="$(printf '\n\t')"
# shellcheck disable=SC2086
exec "$JAVA_BIN" \
  -classpath "$CLASS_PATH" \
  "-XX:ErrorFile=$HOME/java_error_in_pycharm_%p.log" \
  "-XX:HeapDumpPath=$HOME/java_error_in_pycharm_.hprof" \
  ${VM_OPTIONS} \
  "-Djb.vmOptionsFile=${USER_VM_OPTIONS_FILE:-${VM_OPTIONS_FILE}}" \
  ${IDE_PROPERTIES_PROPERTY} \
  "-Xbootclasspath/a:$IDE_HOME/lib/nio-fs.jar" -Djava.system.class.loader=com.intellij.util.lang.PathClassLoader -Didea.vendor.name=JetBrains -Didea.paths.selector=PyCharm2025.2 "-Djna.boot.library.path=$IDE_HOME/lib/jna/amd64" -Djna.nosys=true -Djna.noclasspath=true "-Dpty4j.preferred.native.folder=$IDE_HOME/lib/pty4j" -Dio.netty.allocator.type=pooled "-Dintellij.platform.runtime.repository.path=$IDE_HOME/modules/module-descriptors.dat" -Didea.platform.prefix=Python -Dsplash=true -Daether.connector.resumeDownloads=false -Dcompose.swing.render.on.graphics=true --add-opens=java.base/java.io=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.lang.ref=ALL-UNNAMED --add-opens=java.base/java.lang.reflect=ALL-UNNAMED --add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED --add-opens=java.base/java.nio.charset=ALL-UNNAMED --add-opens=java.base/java.text=ALL-UNNAMED --add-opens=java.base/java.time=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.util.concurrent=ALL-UNNAMED --add-opens=java.base/java.util.concurrent.atomic=ALL-UNNAMED --add-opens=java.base/java.util.concurrent.locks=ALL-UNNAMED --add-opens=java.base/jdk.internal.vm=ALL-UNNAMED --add-opens=java.base/sun.net.dns=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED --add-opens=java.base/sun.nio.fs=ALL-UNNAMED --add-opens=java.base/sun.security.ssl=ALL-UNNAMED --add-opens=java.base/sun.security.util=ALL-UNNAMED --add-opens=java.desktop/com.sun.java.swing=ALL-UNNAMED --add-opens=java.desktop/com.sun.java.swing.plaf.gtk=ALL-UNNAMED --add-opens=java.desktop/java.awt=ALL-UNNAMED --add-opens=java.desktop/java.awt.dnd.peer=ALL-UNNAMED --add-opens=java.desktop/java.awt.event=ALL-UNNAMED --add-opens=java.desktop/java.awt.font=ALL-UNNAMED --add-opens=java.desktop/java.awt.image=ALL-UNNAMED --add-opens=java.desktop/java.awt.peer=ALL-UNNAMED --add-opens=java.desktop/javax.swing=ALL-UNNAMED --add-opens=java.desktop/javax.swing.plaf.basic=ALL-UNNAMED --add-opens=java.desktop/javax.swing.text=ALL-UNNAMED --add-opens=java.desktop/javax.swing.text.html=ALL-UNNAMED --add-opens=java.desktop/javax.swing.text.html.parser=ALL-UNNAMED --add-opens=java.desktop/sun.awt=ALL-UNNAMED --add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED --add-opens=java.desktop/sun.awt.datatransfer=ALL-UNNAMED --add-opens=java.desktop/sun.awt.image=ALL-UNNAMED --add-opens=java.desktop/sun.font=ALL-UNNAMED --add-opens=java.desktop/sun.java2d=ALL-UNNAMED --add-opens=java.desktop/sun.swing=ALL-UNNAMED --add-opens=java.management/sun.management=ALL-UNNAMED --add-opens=jdk.attach/sun.tools.attach=ALL-UNNAMED --add-opens=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED --add-opens=jdk.internal.jvmstat/sun.jvmstat.monitor=ALL-UNNAMED --add-opens=jdk.jdi/com.sun.tools.jdi=ALL-UNNAMED \
  com.intellij.idea.Main \
  "$@"
