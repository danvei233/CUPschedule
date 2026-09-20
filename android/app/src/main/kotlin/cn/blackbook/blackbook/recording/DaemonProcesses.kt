package cn.blackbook.blackbook.recording

/** Uses shell builtins: never starts tr/grep subprocesses for every Android PID. */
internal object DaemonProcesses {
    private fun quote(value: String) = "'" + value.replace("'", "'\\''") + "'"

    fun functions(directory: String, module: String, procRoot: String = "/proc") = """
process_kind() {
  kind=
  is_daemon=0
  has_directory=0
  is_supervisor=0
  [ -r "${'$'}1/cmdline" ] || return 0
  while IFS= read -r -d '' arg; do
    case "${'$'}arg" in
      'cn.blackbook.blackbook.recording.RecorderDaemon') is_daemon=1 ;;
      ${quote(directory)}) has_directory=1 ;;
      ${quote("$module/service.sh")}) is_supervisor=1 ;;
    esac
  done < "${'$'}1/cmdline" 2>/dev/null
  if [ "${'$'}is_daemon" = 1 ] && [ "${'$'}has_directory" = 1 ]; then kind=daemon
  elif [ "${'$'}is_supervisor" = 1 ]; then kind=supervisor
  fi
}
discover() {
  for proc in ${quote(procRoot)}/[0-9]*; do
    process_kind "${'$'}proc"
    [ -z "${'$'}kind" ] || printf '%s %s\n' "${'$'}kind" "${'$'}{proc##*/}"
  done
  return 0
}
"""

    fun discover(directory: String, module: String, procRoot: String = "/proc") =
        functions(directory, module, procRoot) + "\ndiscover\n"

    fun stop(directory: String, module: String, pids: List<Int>, kind: String, graceful: Boolean): String {
        require(kind == "daemon" || kind == "supervisor")
        require(pids.all { it > 1 })
        val terminate = kind == "supervisor" || !graceful
        return functions(directory, module) + """
remaining='${pids.joinToString(" ")}'
deadline=${'$'}((SECONDS + ${if (kind == "daemon" && graceful) 35 else 5}))
${if (terminate) """
for pid in ${'$'}remaining; do
  process_kind "/proc/${'$'}pid"
  if [ "${'$'}kind" = '$kind' ]; then kill -TERM "${'$'}pid" 2>/dev/null || true; fi
done
""" else ""}
while [ -n "${'$'}remaining" ]; do
  pending=
  for pid in ${'$'}remaining; do
    process_kind "/proc/${'$'}pid"
    [ "${'$'}kind" != '$kind' ] || pending="${'$'}pending ${'$'}pid"
  done
  remaining=${'$'}pending
  [ -n "${'$'}remaining" ] || break
  if [ "${'$'}SECONDS" -ge "${'$'}deadline" ]; then
    echo "确认存在的 $kind 进程未退出，PID:${'$'}remaining；未替换 APK"
    exit 1
  fi
  sleep 1
done
"""
    }
}
