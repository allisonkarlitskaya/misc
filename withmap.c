#define _GNU_SOURCE

#include <assert.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <sched.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static void
robust_wait (pid_t child, const char *name)
{
  int wstatus;
  pid_t r;

  do
    r = waitpid (child, &wstatus, 0);
  while (r == -1 && errno == EINTR);

  if (r == -1)
    err (EXIT_FAILURE, "waitpid() on %s failed", name);

  /* no WNOHANG, so it must be this */
  assert (r == child);

  if (WIFEXITED (wstatus))
    {
      if (WEXITSTATUS (wstatus) == 0)
        return;

      errx (EXIT_FAILURE, "%s exited with status %d", name, WEXITSTATUS (wstatus));
    }

  if (WIFSIGNALED (wstatus))
    errx (EXIT_FAILURE, "%s killed by signal %d", name, WTERMSIG (wstatus));

  /* we should have no other possibilities (no WUNTRACED, WCONTINUED, etc.) */
  warnx ("%s changed state unexpectedly.  Terminating.", name);
  kill (child, SIGKILL);
  abort ();
}

static void
spawn_mapcmd (const char *cmd, pid_t pid, const char * const *args, int n_args)
{
  const char *argv[128];
  int argc = 0;

  assert (n_args < 100);

  argv[argc++] = cmd;

  char pidstr[20];
  snprintf (pidstr, sizeof pidstr, "%d", (int) pid);
  argv[argc++] = pidstr;

  for (int i = 0; i < n_args; i++)
    argv[argc++] = args[i];

  argv[argc] = NULL;

  pid_t child;
  int r = posix_spawnp (&child, cmd, NULL, NULL, (char **) argv, NULL);
  if (r != 0)
    err (EXIT_FAILURE, "posix_spawn(\"%s\")", cmd);

  robust_wait (child, cmd);
}

int
main (int argc, char **argv)
{
  int i;
  for (i = 1; i < argc; i++)
    if (strcmp (argv[i], "--") == 0)
      break;

  const char * const *map_args = (const char **) argv + 1;
  int n_map_args = i - 1;

  if (n_map_args == 0)
    errx (EXIT_FAILURE, "must specify at least one mapping triplet");

  if (n_map_args % 3)
    errx (EXIT_FAILURE, "mappings must be specified as groups upper/lower/count");

  /* Skip past the '--', if it was there. */
  if (argv[i])
    i++;

  const char * const *cmd;
  if (argv[i])
    cmd = (const char **) argv + i;
  else
    cmd = (const char*[]) { "bash", NULL };

  int pipefd[2];
  int r = pipe2 (pipefd, O_CLOEXEC);
  if (r != 0)
    err (EXIT_FAILURE, "pipe() failed");

  /* This needs to happen, in order:
   *   - fork()
   *   - parent enters the new user namespace
   *   - child calls new{uid,gid}map()
   *   - parent becomes root in the new namespace
   *   - parent execs the subcommand
   *
   * We use the pipe for the parent to signal to the child that it is
   * done with unshare() and that the child should proceed with the
   * calls to newuidmap and newgidmap.  The parent uses waitpid() to
   * determine when the child is done.  Using a pipe lets the child
   * detect if the parent has quit unexpectedly.
   */

  pid_t parent_pid = getpid ();

  pid_t child_pid = fork ();
  if (child_pid == -1)
    err (EXIT_FAILURE, "fork() failed");

  if (child_pid == 0)
    {
      /* We are the child.  Close the writer end of the pipe so that
       * only the parent has a copy of it.  If the parent exits, it will
       * take the writer with it, and we'll read EOF instead of hanging.
       */
      close (pipefd[1]);

      /* Wait for the signal from the parent. */
      ssize_t s;
      char b;

      do
        s = read (pipefd[0], &b, 1);
      while (s == -1 && errno == EINTR);

      if (s == -1)
        err (EXIT_FAILURE, "read() from parent");

      if (s == 0)
        errx (EXIT_FAILURE, "parent process quit unexpectedly");

      spawn_mapcmd ("newuidmap", parent_pid, map_args, n_map_args);
      spawn_mapcmd ("newgidmap", parent_pid, map_args, n_map_args);

      exit (EXIT_SUCCESS);
    }

  /* Parent */
  r = unshare (CLONE_NEWUSER);
  if (r != 0)
    err (EXIT_FAILURE, "unshare(CLOSE_NEWUSER) failed");

  /* We should have CAP_SETUID now, but we need to wait until the root
   * user is created.  Let the child do its job now.
   */
  ssize_t s;
  do
    s = write (pipefd[1], "", 1);
  while (s == -1 && errno == EINTR);

  if (s == -1)
    err (EXIT_FAILURE, "write() to child");

  assert (s == 1);

  /* Wait for the child to call newuidmap/newgidmap and exit */
  robust_wait (child_pid, "child process");

  /* Now that root exists, become root. */
  r = setresuid (0, 0, 0);
  if (r != 0)
    err (EXIT_FAILURE, "setresuid failed");

  r = setresgid (0, 0, 0);
  if (r != 0)
    err (EXIT_FAILURE, "setresgid failed");

  r = setgroups (0, 0);
  if (r != 0)
    err (EXIT_FAILURE, "setgroups failed");

  /* exec() our command */
  execvp (cmd[0], (char **) cmd);
  err (EXIT_FAILURE, "execp(%s) failed", cmd[0]);
}
