import os
import sys
import subprocess

class GridEngine(object):
    """
    Class containing Grid Engine specific variables and methods
    """
    GE_ENV_PREFIX = 'SGE_'
    LO_ENV_PREFIX = 'LO_'
    GE_CONF = 'qconf'
    GE_ARCH = 'arch'
    GE_SHARE_ON = 'sge_share_mon'
    GE_CONF = 'qconf'
    GE_ARCH_SCR = 'arch'
    GE_SHARE_MON = 'sge_share_mon'
    GE_ROOT = 'SGE_ROOT'
    LO_CONF = 'loconf'
    LO_ARCH_SCR = 'arch'
    LO_SHARE_MON = 'sge_share_mon'
    LO_ROOT = 'LO_ROOT'

    def __init__(self, product='', return_errors=False):
        """
        Constructor initializes the paths for invoking UGE commands.
        return_errors controls whether error messages go to a message box
        pop-up (True) or to stdout (False).
        """

        self.return_errors = return_errors

        # Check whether needed environment variables have been set
        self.__check_env()

        # Check whether the product to be used has been passed to us
        if not product == None:
            # Now try to determine the product via the basedir of the script
            # an compare it against environment variables
            product = self.__check_basedir()

        # We have determined the product we're talking
        # to and can set the commands we'll need to interface with
        if product == 'sge':
            self.qconf = self.GE_CONF
            self.arch = self.GE_ARCH_SCR
            self.share_mon = self.GE_SHARE_MON
            self.root = self.GE_ROOT
        if product == 'lo':
            self.qconf = self.LO_CONF
            self.arch = self.LO_ARCH_SCR
            self.share_mon = self.LO_SHARE_MON
            self.root = self.LO_ROOT


        # The path to the arch script
        self.arch = self.__util_path(self.arch)
        # The path to the qconf command
        self.qconf = self.__bin_cmd_path(self.qconf)
        # The path to the sge_share_mon command
        self.share_mon = self.__utilbin_cmd_path(self.share_mon)

    def run_cmd(self,command):
        """
        Runs commands with the arguments in the string list 'command'
        Returns stdout and stderr as well as error code
        """

        # Run the command and catch stdout/stderr
        p = subprocess.Popen(command,stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE)
        so,se = p.communicate()

        # Check for any errors and display stderr in a error message box if so
        if p.returncode != 0 or se != '':
            if p.returncode != 0:
                # Exit status was non-zero. So create an error message
                msgstr = "Error: return code %s\n" % str(p.returncode)
                msgstr = msgstr + "Running command:"
                msgstr = msgstr + '\n' + ' '.join(command) + '\n'
                msgstr = msgstr + "Error output:"
            else:
                # There might still be error output despite the error status
                # was 0. Setup an empty message for that.
                msgstr = ""
            if se != '':
                # We have stderr output so lets paste that into the msg str
                msgstr = msgstr + '\n' + se
            if self.return_errors:
                # And display the message in a message box
                return (so, msgstr, p.returncode)
            else:
                # Or print it to stdout (only for debugging)
                sys.stderr.write(msgstr)
                return (so, msgstr, p.returncode)
                # sys.exit(p.returncode)
        # Return the output streams the error code to the caller; at this
        # point only the stdout and the error code is being used outside of
        # this function
        return (so,se,p.returncode)

    def read_share_tree(self):
        """
        Read the share tree via 'qconf -sstree' and return sdout/err
        """
        so,se,err = self.run_cmd([self.qconf, '-sstree'])
        return so.split('\n')

    def __util_path(self,command):
        """
        Return utilbin path. Requires SGE_ROOT or LO_ROOT env var to be set
        """
        return os.environ[self.root] + '/util/' + command

    def __utilbin_cmd_path(self,command):
        """
        Determine utilbin path for Grid Engine command via the arch script
        Requires SGE_ROOT or LO_ROOT env var to be set
        """
        so,se,err = self.run_cmd([self.arch])
        arch = so.split('\n')[0]
        return os.environ[self.root] + '/utilbin/' + arch + '/' + command

    def __bin_cmd_path(self,command):
        """
        Determine binary path for Grid Engine command via the arch script
        Requires SGE_ROOT or LO_ROOT env var to be set
        """
        so,se,err = self.run_cmd([self.arch])
        arch = so.split('\n')[0]
        return os.environ[self.root] + '/bin/' + arch + '/' + command

    def __check_env(self):
        """
        Checks whether we have required env vars being
        set. We actually might have both sets, for UGE and LO at the
        same time. We need at least one being complete.

        If we don't have the required env vars then this method will print an
        error message and call sys.exit(1). Might want to change this to
        raising an exception at some point.
        """
        # The required list of env vars (without the product prefix)
        # ck_env = [ 'ROOT', 'CELL', 'QMASTER_PORT' ]
        ck_env = [ 'ROOT', 'CELL' ]
        # Capture those which are *not* set for GE and LO
        ge_env_not_set = filter(lambda s: s not in os.environ,
            map(lambda s: self.GE_ENV_PREFIX + s, ck_env))
        lo_env_not_set = filter(lambda s: s not in os.environ,
            map(lambda s: self.LO_ENV_PREFIX + s, ck_env))

        # One of both env_not_set lists now still should be empty, meaning we
        # have all env vars needed for the corresponding product
        # If not at least one of them is complete then stree-edit.py
        # won't work. Print error message and exit.
        if len(ge_env_not_set) > 0 and len(lo_env_not_set) > 0:
            sys.stderr.write('Error: Must have environment variables set.')
            sys.stderr.write('%s %s' % str(ge_env_not_set), str(lo_env_not_set))
            sys.stderr.write('You might want to source <[sge,lo]_root>/<cell>/common/settings.[csh,sh]')
            sys.stderr.write('Exiting.')
            sys.exit(1)

    def __check_basedir(self):
        """
        Checks whether either the UGE ROOT env var or the LO ROOT
        env var are part of the execution path of stree-edit.py.
        The one which matches (it should be only one) tells us which
        product we need to be talking to.

        If we can't find a match then this method will print an
        error message and call sys.exit(1). Might want to change this to
        raising an exception at some point.
        """
        bindir = os.path.dirname(sys.argv[0])
        basenm = os.path.basename(sys.argv[0])
        ge_root = self.GE_ENV_PREFIX + 'ROOT'
        if ge_root in os.environ and bindir.find(ge_root):
            # It's UGE
            product = 'sge'
        lo_root = self.LO_ENV_PREFIX + 'ROOT'
        if lo_root in os.environ and bindir.find(lo_root):
            # It's LO
            product = 'lo'
        if product == '':
            # We've got no match. So we can't really guess what it is. The
            # installation must use non-standard paths to stree-edit.py
            # which aren't part of the ROOT dir. So we have to let the
            # user tell us which one it should be.
            sys.stderr.write('The path to %s is %s.\n' % basenm, bindir)
            sys.stderr.write('That path is not contained in any of the env vars %s and %s\n' % ge_root, lo_root)
            sys.stderr.write('Please use --product {sge|lo} option and invoke again.')
            sys.stderr.write('Exiting.')
            sys.exit(1)

        # We've got this far so return the prodcut string we have set above
        return product

