#!/usr/bin/python
#___INFO__MARK_BEGIN__
#############################################################################
#
#  This code is the Property, a Trade Secret and the Confidential Information
#  of Univa Corporation.
#
#  Copyright Univa Corporation. All Rights Reserved. Access is Restricted.
#
#  It is provided to you under the terms of the
#  Univa Term Software License Agreement.
#
#  If you have any questions, please contact our Support Department.
#
#  www.univa.com
#
###########################################################################
#___INFO__MARK_END__
"""
CrayBasil.py -- Command-line tool to handle the XML query and XML reponse
parsing of the Cray XC30 BASIL interface layer for integration with Univa Grid
Engine.

Currently implemented options are:
   --debug : debug output
   --verbose : verbose XML protocol tracing output (also for debugging)
   --reserveNodes=N : <nodes>,<width>,<depth>,<nppn> for reservation
   --jobid=ID : the Grid Engine job ID the reservation is made for on the Cray
   --user=username : the username for which the reservation is being made
   --confirmRes=reservID : the reservation ID reservID to confirm
   --cancelRes=reservID : the reservation ID reservID to cancel
   --names : inventory call to display all node names which are available
             (execution node names by default)
   --nodes : inventory call to display the number of available nodes
             (execution nodes by default)
   --interactive : switch --names/--nodes to relate to interactive nodes
   --alps : call to display the ALPS version being used
   --basil : call to display the supported BASIL versions
   --adminCookie=aCookie : admin Cookie aCookie to be supplied with the
                           reservation cancellation call. Tries to retrieve
                           admin Cookie if 'auto' is set for aCookie.
   --createAdminCookie : retrieve and print out current admin Cookie.
   --sessionId : returns the sid (session id of the process)
   --file : use specified file name in lieu of an XML response returned by
       BASIL. For debugging purposes. No XML query will be issued.
   --rur=<path_to_rur_file.txt> : Parses the RUR output from "file" plugin.
   --jobs: list all job IDs and reservations that are associated with a reservation
   --orphanedReservations: lists all reservation IDs without any associated active UGE job

Return values:
   0  : Success
   1  : BASIL request did not return with SUCCESS
   2  : Command-line parsing errors
   3  : Required environment variables were missing
   4  : Error in running Grid Engine command
   5  : Couldn't retried reservation ID from job context
   6  : Couldn't find apbasil binary
   7  : Error in admin cookie retrieval
   8  : Couldn't read XML from file if --file was used
   9  : Failure while executing apbasil request and reading the response
   10 : Timeout while executing apbasil
   11 : Error during RUR parsing
   12 : Error while accessing given file
   13 : Error while parsing accounting records
   14 : Coudn't find apstat binary
   15 : No orphaned reservations found
"""

import os
import pwd
import sys
import subprocess
import time
import signal
import re
import xml.parsers.expat
import distutils.spawn
from xml.dom import minidom
from optparse import OptionParser
# for PAGG
from ctypes import *

def errExit(val, msg):
   """
   Exit-with-error utility function

   Prepends error message in argument "msg" with "Error: " and appends a
   newline
   Exits with error value "val"
   """
   sys.stderr.write("Error: " + msg + "\n")
   sys.exit(val)

class TimeoutException(Exception):
    # Create our own timeout exception
    pass

class timeout(object):
   """
   Creates a timeout decorator. For a class to be used as a decorator it needs
   to implement the handling of decorator arguments in __init__ and the class
   also needs to be callable, i.e. it needs to implement a __call__ method
   where the replacement for the decorated function is being created and
   returned.
   """
   def __init__(self, timeout_time, default):
      """
      Handles the decorator arguments - just make them class variables
         timeout_time   : time after which timeout occurs
         default        : default value to be returned if timeout occurs
      """
      self.timeout_time = timeout_time
      self.default = default

   def __call__(self, f):
      """
      Makes class callable. f is the decorated function and __call__
      returns its replacement.
      """
      def new_f(*args, **kwargs):
         """
         Replacement for the decorated function, i.e. new_f gets invoked
         instead of f. *args and **kwargs are the arguments f gets called
         with. Here the replacement function will wrap f with a timeout.
         """
         def timeout_handler(signum, frame):
            # frame isn't used but might be required as signature for
            # signal.signal (need to check - not done so far)
            raise TimeoutException()

         # Save previous handler to restore later and install above one
         old_handler = signal.signal(signal.SIGALRM, timeout_handler)
         signal.alarm(self.timeout_time) # triger alarm in timeout_time seconds

         # Pre-set default return value in case timeout occurs and no values
         # get returned from calling f below.
         retval = self.default

         # Try to call function with timeout
         try:
            # if finishes in time then just return the result
            retval = f(*args, **kwargs)
         except TimeoutException:
            pass
         finally:
            # Cancel timeout alarm
            signal.alarm(0)
            # And re-install old signal handler
            signal.signal(signal.SIGALRM, old_handler)
         return retval
      return new_f

def getAdminCookie():
   """
   Function returning adminCookie required from --confirmRes.
   Gets called when --adminCookie=auto or when option --createAdminCookie
   has been used.
   """
   try:
      cdll.LoadLibrary("libjob.so")
      libjob = CDLL("libjob.so")
      # Need the user id of the job owner (this script is executed as root)
      # (USER environment variable)
      uid = pwd.getpwnam(os.environ["USER"]).pw_uid
      jobid = str(libjob.job_create(0, uid, 0))
      if jobid == "-1":
         errExit(7, "failed to get a PAG with job_create() - abort.")
      else:
         return jobid
   except:
      errExit(7, "couldn't execute job_create() from libjob.so")

def CLI():
   """
   Command-line parsing. Parsing options are defined in cliFlags dictionary
   and the parsed options will be stored in the object 'cli'

   Also exports CLI option descriptor cliFlags and access position IDs
   optparsetype, optdefault, opthelp, optkey, optrettype and opterrmsg
   (see the comments in their definition for their meaning)

   Furthermore exports keyopt which points to the option which triggers the
   query (as opposed to options which add additional information).

   Uses OptionParser from optparse module
   """

   global cli   # make cli object global so it can be accessed from anywhere
   global cliFlags    # option handling descriptor
   global keyopt  # key option which will trigger the BASIL query
   global clioptset

   # Layout of list elements in cliFlags
   # optparsetype the type of option in option parser
   # optdefault   default value when option not set
   # opthelp      help message of option
   # optkey       True when a XML ALPS query is done - boolean determining whether option is keyoption
   # optrettype   return value type for query triggered by keyoption
   # opterrmsg    error message if failure for query triggered by keyoption
   global optparsetype, optdefault, opthelp, optkey, optrettype, opterrmsg
   optparsetype, optdefault, opthelp, optkey, optrettype, opterrmsg \
      = range(6)
   # make global

   # cli option specification - key is option string; see layout of value
   # list above
   cliFlags = {
      "alps" : ["bool", False, "BASIL ENGINE QUERY: Prints the ALPS version of apbasil",
              True, "Str", "ALPS version query was not successful."],
      "basil" : ["bool", False, "BASIL ENGINE QUERY: Prints the BASIL version of apbasil",
              True, "Str", "BASIL version support query was not successful"],
      "reserveNodes" : ["str", "", "BASIL RESERVATION request: <nodes>,<width>,<depth>,<nppn>. Needs --jobid to be set or will attempt to get from env vars.",
              True, "Int", "Reservation request was not successful"],
      "confirmRes" : ["str", "", "BASIL RESERVATION CONFIRMATION request: Confirm reservation with the given ID. Set to 'auto' to self-detect from job context.",
              True, "Str", "Reservation confirmation was not successful"],
      "cancelRes" : ["str", "", "BASIL RESERVATION CANCELLATION request: Cancel reservation with the given ID. Set to 'auto' to self-detect from job context.",
              True, "Str", "Reservation cancellation was not successful"],
      "nodes" : ["bool", False, "BASIL INVENTORY request: Prints amount of compute nodes, NUMA node, and core per NUMA node",
              True, "Str", "Node count inventory request was not successful."],
      "names" : ["bool", False, "BASIL INVENTORY request: Prints all node names as space separated list (exec hosts by default)",
              True, "Str", "Hostname list inventory request was not successful."],
      "interactive" : ["bool", False, "Relate --nodes or --names option to interactive nodes instead",
              False, "", ""],
      "adminCookie" : ["str", "", "BASIL RESERVATION CONFIRMATION adminCookie: Admin cookie number from reservation",
              False, "Str", ""],
      "user" : ["str", "$USER", "User name for job request. Requires --reserveNodes and --jobid to be set as well.",
              False, "", ""],
      "jobid" : ["str", "", "BASIL RESERVATION needs a jobid <jobid>.<taskid>. Requires --reserveNodes to be set as well.",
              False, "", ""],
      "debug" : ["bool", False, "Verbosity for debugging",
              False, "", ""],
      "file" : ["str", "", "Don't do an XML query but parse response from XML-file being specified.",
              False, "", ""],
      "verbose" : ["bool", False, "Protocol trace for debugging",
              False, "", ""],
      "sessionId" : ["bool", False, "Returns the sid (session id) of the current process.",
              False, "", ""],
      "createAdminCookie" : ["bool", False, "Returns a newly created admin cookie.",
              False, "", ""],
      "rur" : ["str", "", "Parses the given RUR file (which is created by the file output plugin).",
              False, "Str", "Parsing RUR file failed"],
      "jobs" : ["bool", False, "Returns all jobs associated with current Cray reservations.",
              False, "", ""],
      "orphanedReservations" : ["bool", False, "Returns all broken reservations for which the UGE job is not active.",
              False, "", ""]
   }

   if len(sys.argv) == 0:
      errExit(1, "No argument specified, try CryBasil.py --help")

   # create parser object
   parser = OptionParser()

   for key in cliFlags.keys():
      # Look through dictionary and set options for parsing
      vals = cliFlags[key]
      if vals[optparsetype] == "bool":
         # Boolean CLI options require either the store_false or store_true
         # action to be set
         if vals[optdefault]:
            store="store_false"
         else:
            store="store_true"
         parser.add_option("--" + key, action=store,
            dest=key, default=vals[optdefault], help=vals[opthelp])
      else:
         # str or int options just require the "store" action
         parser.add_option("--" + key, action="store",
            dest=key, type=vals[0], default=vals[optdefault], help=vals[opthelp])

   # Parse the arguments
   (cli, otherargs) = parser.parse_args()
   # Defined cli-options are now accessible via cli.optionname
   # Other options on the command line are stored in otherargs

   # Little helper function which simplifies checking whether non-boolean CLI
   # options have been set (i.e. are unequal from their default).
   # Is accessible globally
   clioptset = lambda x: cliFlags[x][optdefault] <> getattr(cli, x)

   # Find key option and make sure two key options aren't set at the same
   # time. Also check for whether at least one option (any option) has been
   # specified.
   keyopt = ""
   someopt = False
   for key in cliFlags.keys():
      # compare key option setting in cli object getattr(cli, key) with
      # default in cliFlags. If different then this option was set and if it
      # is one of the potential key options then set it as key option or
      # print an error if another key option was already set
      if clioptset(key):
         # We have at least on option unequal to the default - i.e. it has
         # been set
         someopt = True
         if cliFlags[key][optkey]:
            if keyopt:
               errExit(2, "must not use --" + key + " together with --" + keyopt)
            else:
               keyopt = key
   if not someopt:
      # No option has been set - bail out
      print "Must specify at least one option switch!\n"
      parser.print_usage()
      print "Use the --help option for more information.\n"
      errExit(2, "Nothing to do - exiting.")

   # Read in jobid from environment variables JOB_ID and SGE_TASK_ID if --jobid
   # was not used
   if not clioptset("jobid"):
      try:
         taskID = os.environ["SGE_TASK_ID"]
         cli.jobid = os.environ["JOB_ID"]
         if taskID <> "undefined":
            cli.jobid = cli.jobid + "." + taskID
      except:
         pass
         # cli.jobid may still contain the default if it was not set in the
         # environment and not via the --jobid flag

   # Make sure that --reserveNodes contains <nodes>,<width>,<depth>,<nppn>
   if clioptset("reserveNodes"):
      job_requests = cli.reserveNodes.split(",")
      if len(job_requests) != 3 and len(job_requests) != 4:
         errExit(2, "--reserveNodes doesn't have format <nodes>,<width>,<depth>[,<nppn>]")

   # Make sure --reserveNodes is set together with --jobid
   # --reserveNodes/--joid are set when the value returned from parsing is
   # different from default defined in cliFlags
   if clioptset("reserveNodes") and not clioptset("jobid"):
         errExit(2, "--jobid and --reserveNodes must be set together")

   # Make sure --reserveNodes and --jobID are set when --user has been set
   if clioptset("user"):
      if not clioptset("reserveNodes"):
         errExit(2, "--user was set; need to set --reserveNodes as well.")
      if not clioptset("jobid"):
         errExit(2, "--user was set; need to set --jobid as well.")
   else:
      # Get user from environment variable when --user was not set
      cli.user = os.environ["USER"]

   # Make sure either --names or --nodes is set when --interactive is set
   if clioptset("interactive") and not (clioptset("names") or clioptset("nodes")):
         errExit(2, "--names or --nodes must be set when --interactive is used.")

   if clioptset("adminCookie"):
      if cli.adminCookie == "auto":
      	cli.adminCookie = getAdminCookie()

   # Make sure --confirmRes and --adminCookie are both set at once
   if clioptset("confirmRes") and not clioptset("adminCookie") \
         or not clioptset("confirmRes") and clioptset("adminCookie"):
      errExit(2, "--adminCookie and --confirmRes must be set together.")

   # Check for feasible values for --confirmRes and --cancelRes
   if clioptset("confirmRes") \
         and cli.confirmRes <> "auto" and not cli.confirmRes.isdigit():
      errExit(2, "--confirmRes must either be 'auto' or a number.")
   if clioptset("cancelRes") \
         and cli.cancelRes <> "auto" and not cli.cancelRes.isdigit():
      errExit(2, "--confirmRes must either be 'auto' or a number.")

   # Print out how all options were set and parsed for debugging
   if cli.debug:
      for key in cliFlags.keys():
         print "Results of option parsing:"
         print key + ": " + str(getattr(cli, key))
      print


class GridEngine(object):
   """
   Class for running Grid Engine CLI commands.

   Exports class functions for all binaries contained in the Grid Engine
   binary directory, i.e. there will be a function qconf(args) with which you
   can run the qconf command with the arguments in 'args'. The same is true
   for qstat and so on.
   """
   def __init__(self):
      # Get binary path or print error if not set.
      # When it exists we assume we are inside of a Grid Engine job and can
      # run Grid Engine commands.
      try:
         ge_path = os.environ["SGE_BINARY_PATH"]
      except:
         errExit(3, "SGE_BINARY_PATH not in environment. Required to find Grid Engine binaries.")

      # Set functions for all binaries in the binary directory
      def setter(c):
         # Need a closure so we can pass the cmd to be executed to each
         # function instance without it being overwritten
         return lambda x: self._run(c, x) # c will be the command & x the args
      for cmd in os.listdir(ge_path):
         # Now create all the functions passing the full path to the executable
         # to each
         setattr(self, cmd, setter(ge_path + "/" + cmd))

      # Check whether everything went fell and we have Grid Engine command
      # access methods. If not then print an informative error message
      try:
         getattr(self, "qconf")
         getattr(self, "qstat")
      except:
         errExit(3, "failed to setup access methods for Grid Engine binaries. Maybe issue with readability of the binary directory or with file access permission?")

   def _run(self, cmd, args):
      """
      Runs Grid Engine CLI command contained in string 'cmd' with arguments in
      args. Args can either be a string or a list with individual strings
      containing the positional parameters.
      """
      # Depending on argument type assemble command to be run in list 'cmdl'
      cmdl = [cmd]
      if type(args) == str:
         cmdl += args.split(" ")
      elif type(args) == list:
         cmdl += args
      else:
         errExit(4, "Can't run Grid Engine command: unsupported argument type of "
            + str(args) + " = " + str(type(args)))
      # Run the command
      try:
         p = subprocess.Popen(cmdl, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
         so,se = p.communicate()
      except:
         errExit(4, "got exception while invoking " + " ".join(cmdl))

      # Check for error codes
      if p.returncode:
         errExit(4, "Running " + " ".join(cmdl) + " resulted in error code: "
            + str(p.returncode) + "\nError Output:\n" + se)

      # And for error output
      if se:
         print "Warning: command " + " ".join(cmd) + " has returned the \
            following stderr output: " + se

      # Return stdout
      return so

def getReservationID():
   """
   Retrieve and return reservation_id: from cli options for either the
   cancel or confirm query or, if nowhere set, from 'qstat -j job_id' ouput
   and the context variable definition contained in there.
   """
   # --confirmRes/--cancelRes can either be "" (default = not set) or
   # "auto" (retrieve from context) or a number. If a number then return
   # that as reservation ID. Note that only one of them will be set to a
   # non default value. This was checked by the CLI method.
   if clioptset("confirmRes") and cli.confirmRes <> "auto":
      return cli.confirmRes
   if clioptset("cancelRes") and cli.cancelRes <> "auto":
      return cli.cancelRes

   # Check for require env vars
   try:
      jobID = os.environ["JOB_ID"]
      taskID = os.environ["SGE_TASK_ID"]
   except:
      errExit(3, "JOB_ID and SGE_TASK_ID variables must be set to retrieve the reservation ID.")

   # For regular jobs SGE_TASK_ID is set to "undefined". We use "1"
   # instead.
   if taskID == "undefined":
      taskID = "1"
   # The job context will contain a variable called 'reservation_<taskid>'
   reserv_ctxt_var = "reservation_" + taskID

   # Instantiate the GridEngine object, run the qstat -j command and parse
   # it for the context variable
   ge = GridEngine()
   so = ge.qstat(["-j", jobID])
   # Could look for reserv_ctxt_var right away but in case this string
   # appears anywhere else in the qstat -j output we cut off at the context
   # var section first
   head, sep, tail = so.partition("context:")
   # Now split at reserv_ctxt_var.
   head, sep, tail = tail.partition(reserv_ctxt_var + "=")
   # tail starts with what we look for plus a newline and other stuff so
   # split at the newline to find the reservation ID in head
   head, sep, tail = tail.partition("\n")
   # an array job has multpile reservation ids set (CSV)
   head, sep, tail = head.partition(",")

   # Make sure it's a number and then return it
   if head.isdigit():
      return head
   else:
      errExit(5, "Unable to retrieve reservation ID from job context. Got: " +
         head)


class parseXML(object):
   """
   Object parsing the Basil XML response.

   Externally accessible are a set of return values:
      returnInt, returnStr, returnStatus

   Internal functions are the various parser functions depending on the type
   of BASIL query and some helper functions.

   Uses the expat parser from the xml module
   """
   def __init__(self, xmldoc):
      """
      Define and preset potential return values and setup the expat XML
      parser
      """
      self.xmldoc = xmldoc
      self.returnInt = 0
      self.returnStr = ""
      self.returnStatus = ""
      if cli.interactive:
         self.htype = "INTERACTIVE"
      else:
         self.htype = "BATCH"

      # Variables for node statistics
      if cli.nodes:
         self.totalUpNodes = 0
         self.nodeOK = False
         self.nodeName = ""
         self.segmentCtr = 0
         self.processorCtr = 0
         self.segmentsPerNode = 0
         self.processorsPerNode = 0
         self.processorCtrSum = 0
         self.processorsPerSegment = 0
         self.role = ""
         self.nodeMap = {}
         self.procSegMap = ""

      # Create expat parser
      self.p = xml.parsers.expat.ParserCreate()
      # Assign handler for XML element starts; handler name is based on
      # key option (method object retrieved with getattr)
      self.p.StartElementHandler = getattr(self, "_startElem_" + keyopt)
      # End elem handler just need for node statistics, i.e. for --nodes
      # switch
      if cli.nodes:
         self.p.EndElementHandler = self._endElem_nodes
      # Parse the doc
      self.p.Parse(self.xmldoc)

   def _checkStatus(self, name, attrs):
      """ Returns value of status attrib in ResponseData tag """
      if name == "ResponseData":
         self.returnStatus = attrs["status"]

   def _startElem(self, name, attrs, tag, attrname):
      """
      Helper function implementing most common parsing pattern
      """
      if self.returnStatus == "SUCCESS":
         # If previous invocation has detected success
         if name == tag:
            # If we're in the XML tag relevant for this query then set
            # return value as defined in cliFlags and with value from
            # attribute depending on query type
            setattr(self, "return" + cliFlags[keyopt][optrettype], attrs[attrname])
      self._checkStatus(name, attrs)

   def _startElem_names(self, name, attrs):
      """ Special parser function for --names CLI option """
      if self.returnStatus == "SUCCESS":
         # If previous invocation has detected success
         if name == "Node":
            # If this is a Node tage and if the node is up and of the node
            # type we care about (BATCH or INTERACTIVE) then expand and
            # string list with hostnames
            if attrs["role"] == self.htype and attrs["state"] == "UP":
               if self.returnStr:
                  self.returnStr += " " + attrs["name"]
               else:
                  self.returnStr += attrs["name"]
      self._checkStatus(name, attrs)

   def _startElem_nodes(self, name, attrs):
      """ Special parser function for --nodes CLI option """
      if self.returnStatus == "SUCCESS":
         if name == "Node":
            # If this is a Node tage and if the node is up and of the node
            # type we care about (BATCH or INTERACTIVE) then increase the
            # node count

            # save role for check in _endElem_nodes whether we are to collect
            # BATCH or INTERACTIVE node statistics
            self.role = attrs["role"]
            if self.role == self.htype and attrs["state"] == "UP":
               # Check whether node is of the right type (INTERACTIVE or
               # BATCH). If so then mark it as such, count the node and
               # remember its name (that latter for potential error outputs)
               self.totalUpNodes +=1
               self.nodeOK = True
               self.nodeName = attrs["name"]
         if self.nodeOK:
            # If a preceding node element was identified as being OK then
            # Segment and Processor elements "inside" need to be counted
            if name == "Segment":
               self.segmentCtr +=1
            if name == "Processor":
               self.processorCtr += 1
      self._checkStatus(name, attrs)

   def _endElem_nodes(self, name):
      """
      Parser function used for closing XML elements used for gathering node
      statistics, in particular the number of nodes overall, the number of
      sgements (numa nodes - usually sockets) per node and the number of
      processors (cores) per segment/socket.

      Also checks on consistency - number of segments and
      processors need to be equal across all nodes.

      Returns error message otherwise. Results are returned in self.returnStr
      (either statistics or error message) and in self.returnStatus
      (SUCCESS, ERROR or INCONSISTENCY)

      For interactive nodes (--interactive option together with --names) only the
      number of nodes overall of that type are returned
      """
      def addOrExpand(d, k, v):
         """
         Helper method which either adds a new elem to a dict or expands and
         existing one. By expand we mean expanding the value of a dict entry.
         That value is a list here.
         """
         if k in d:
            d[k] += [v]
         else:
            d[k] = [v]

      if self.htype == "INTERACTIVE":
          # if --interactive was specified
          if name == "NodeArray" and self.returnStatus == "SUCCESS":
             # when done with all nodes just return the node count
             self.returnStr = str(self.totalUpNodes)
          # don't do anything else in that case here
          return
      if self.role == "INTERACTIVE":
          # Without --interactive (so when counting BATCH nodes) but while dealing
          # with an INTERACTIVE node do nothing other than resetting 'role'
          self.role = ""
          return
      # All of the below is for BATCH nodes while we handle the case without
      # --interactive being specified
      if name == "Node" and self.nodeOK:
         # When we return from a node element ...
         # Add entry to node map dict - or expend existing one with node name
         addOrExpand(self.nodeMap, self.procSegMap, self.nodeName)
         if not self.segmentsPerNode:
            # set segs-per-node - used for output if all is consistent, so
            # need to set this only once. Not used in case of inconsistencies
            self.segmentsPerNode = self.segmentCtr
         # Reset stuff for next node ...
         self.nodeOK = False
         self.segmentCtr = 0
         self.processorCtrSum = 0
         self.procSegMap = ""
      if name == "Segment" and self.nodeOK:
         # When we return from a segment element ...
         # Add up processor count for later use when exiting the node
         self.processorCtrSum += self.processorCtr
         # set map of procs-per-seg: a string of the form '8-7-8' meaning 8
         # procs in 1st seg, 7 in 2nd, 8 in 3rd.
         if self.procSegMap:
            self.procSegMap += "-" + str(self.processorCtr)
         else:
            self.procSegMap = str(self.processorCtr)
         # Store procs-per-seg # for output if all is consistent. Not used in
         # case of inconsistencies so need to do this only once.
         if not self.processorsPerSegment:
            self.processorsPerSegment = self.processorCtr
         # Reset counter
         self.processorCtr = 0
      if name == "NodeArray" and self.returnStatus == "SUCCESS":
         # Done with all nodes. So if there were no inconsistencies then
         # put statistics into return string
         if len(self.nodeMap) == 1:
            # if there's only one entry in the node map then all was
            # consistent, so create desired info output
            self.returnStr = str(self.totalUpNodes) + "," + \
                             str(self.segmentsPerNode) + "," + \
                             str(self.processorsPerSegment)
         elif len(self.nodeMap) == 0:
            # Empty node map means not even a single BATCH node has been found
            self.returnStr = "No nodes of type BATCH found! Nodes designated " \
               + "for executing Univa Grid Engine jobs need to be of type " \
               + "BATCH."
            self.returnStatus = "ERROR"
         else:
            # there have been inconsistencies so print the node map in a nice
            # way
            self.returnStr = "Inconistencies in node setup. Nodes have the " \
               + "following map of processors per segment:\n"
            for key in self.nodeMap.keys():
               self.returnStr += str(key) + ": "
               self.returnStr += " ".join(str(x) for x in self.nodeMap[key]) + "\n"
            # and indicate it via the return status
            self.returnStatus = "INCONSISTENCY"

   def _startElem_alps(self, name, attrs):
      """ Parser for --alps option ==> standard parser behavior """
      self._startElem(name, attrs, "Engine", "version")

   def _startElem_basil(self, name, attrs):
      """ Parser for --basil option ==> standard parser behavior """
      self._startElem(name, attrs, "Engine", "basil_support")
      # Just a small reformatting of the output string
      self.returnStr = self.returnStr.replace(",", " ")

   def _startElem_reserveNodes(self, name, attrs):
      """ Parser for --reserveNodes option ==> standard parser behavior """
      self._startElem(name, attrs, "Reserved", "reservation_id")

   def _startElem_confirmRes(self, name, attrs):
      """ Special parser for the --confirmRes option """
      if self.returnStatus == "SUCCESS":
         # Simple confirm string in case of sucess
         self.returnStr = "Confirmed"
      self._checkStatus(name, attrs)

   def _startElem_cancelRes(self, name, attrs):
      """ Special parser for the --cancelRes option """
      if self.returnStatus == "SUCCESS":
         # Simple cancellation confirm string in case of sucess
         self.returnStr = "Cancellation in progress"
      self._checkStatus(name, attrs)


def feedNreadBASIL(requestXML, parseopt):
   """
   Writes XML request contained in paramter requestXML to stdin of apbasil
   and reads apbasil's XML output, parses the XML and returns the parsed
   document.

   Uses minidom from xml.dom module for XML parsing.
   """
   # decorated with 30 sec timeout and with the default return value in
   # the tuple, i.e. empty output, error output and no subprocess object
   @timeout(30, ("","",None))
   def _run_apbasil(cmd, xml):
      """
      Function for starting apbasil so we can decorate it with a timeout
      """
      # Fork the command
      p = subprocess.Popen(cmd,
         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      # Feed the XML request into it
      p.stdin.write(xml)
      # Make double certain the data is written
      # Do this in a try clause as there are cases where the fsync does not
      # work
      try:
         p.stdin.flush()
         os.fsync(p.stdin.fileno())
      except:
         pass
      # Get and return stdout and stderr plus return the suprocess object
      so,se = p.communicate()
      return so,se,p

   if cli.verbose:
      # Print XML request if --verbose has been specified on command line
      print requestXML + '\n'

   if not clioptset("file"):
      # cli.file was not specified, so no debugging case but the regular case
      # of executing apbasil

      # The apbasil command to be executed
      apbasil = distutils.spawn.find_executable("apbasil")
      if not apbasil:
         errExit(6, "can't locate apbasil in current binary search path:\n" +
           os.environ["PATH"])
      command = [ apbasil ]

      # Try to run the apbasil command
      try:
         so,se,proc = _run_apbasil(command, requestXML)
      except:
         print "Unexpected error:", sys.exc_info()[0]
         errExit(9, "failure in executing command " + command[0] \
            + ", feeding the request to it and reading the XML response.")

      # If proc is none then _run_apbasil has returned the default value
      # specified in the timeout decorator ==> a timeout has occurred.
      if not proc:
         # No point in going further
         errExit(10, "encountered timeout of 30 seconds while attempting to run apbasil!")

      # Error output in case of error codes or error messages are returned
      # Skip if proc==None ==> timeout
      if proc.returncode <> 0 or se <> "":
         errmsg = "Error: return code %s\n" % str(proc.returncode)
         errmsg += "Running command:\n" + " ".join(command) + "\n"
         errmsg += "XML Request:\n" + requestXML + "\n"
         errmsg += "Error returned by command:\n" + se  + "\n"
         sys.stderr.write(errmsg)
   else:
      # Get query response from XML file for debug purposes
      try:
         so = open(cli.file, "r").read()
      except:
         errExit(8, "couldn't open file " + cli.file + " as source for debug XML response.")

   if cli.verbose:
      # Use minidom parser to product nicely formatted verbose output
      # Skip if proc==None ==> timeout
      xmldoc = minidom.parseString(so)
      print xmldoc.toxml()

   # Use expat parser for content processing
   p = parseXML(so)
   # return the parser object which contains the various return values
   # Or return None in case of a timeout
   return p


class BasilQuery(object):
   """
   Object for handling BASIL queries.
   Defines all possible XML query strings in the __init__ function.
   Provides a handle function which selects the appropriate query based on
   CLI options and then process the response.
   """
   def __init__(self):
      """
      Define the BASIL query XMLstrings
      """
      # ------------------------------
      # BASIL 1.0 inventory invocation
      # ------------------------------
      self.nodesQuery = '''<?xml version="1.0"?>
<BasilRequest protocol="1.2" method="QUERY" type="INVENTORY"/>'''
      
      self.namesQuery = self.nodesQuery

      # ------------------------------
      # BASIL 1.1 engine query invocation
      # ------------------------------
      self.alpsQuery = '''<?xml version="1.0"?>
<BasilRequest protocol="1.1" method="QUERY" type="ENGINE"/>'''

      self.basilQuery = self.alpsQuery

      # -----------------------------
      # BASIL 1.2 RESERVATION request
      # -----------------------------
      # 1.1 version introduced mode "exclusive"
      # 1.2 version needs batch_id set to jobid

      # Reservation query with width (amount of processing elements) and depth (amount of cores per pe)
      nodesWidthDepthQuery = '''<?xml version="1.0"?>
<BasilRequest protocol="1.2" method="RESERVE">
<ReserveParamArray user_name="$USERNAME$" batch_id="$BATCHID$">
<ReserveParam architecture="XT" reservation_mode="EXCLUSIVE" width="$WIDTH$" depth="$DEPTH$"/>
</ReserveParamArray>
</BasilRequest>'''

      # Reservation query with nppn (processing elements per compute node)
      nodesNPPNQuery  = '''<?xml version="1.0"?>
<BasilRequest protocol="1.2" method="RESERVE">
<ReserveParamArray user_name="$USERNAME$" batch_id="$BATCHID$">
<ReserveParam architecture="XT" reservation_mode="EXCLUSIVE" width="$WIDTH$" depth="$DEPTH$" nppn="$NPPN$"/>
</ReserveParamArray>
</BasilRequest>'''

      # --reserveNodes of format <nodes>,<width>,<depth>[,<nppn>]
      job_requests = cli.reserveNodes.split(",")

      if len(job_requests) >= 3:
         # if >=3 then --reserveNodes was used, so fill the query with
         # appropriate data
         if len(job_requests) == 4 and job_requests[3] != 0:
            # nppn was set so use the right query and put it in there
            self.reserveNodesQuery = nodesNPPNQuery
            self.reserveNodesQuery = self.reserveNodesQuery.replace("$NPPN$", job_requests[3])
         else:
            # no nppn, so use the simpler query
            self.reserveNodesQuery = nodesWidthDepthQuery

         # Set width and depth as specified on command-line
         self.reserveNodesQuery = self.reserveNodesQuery.replace("$WIDTH$", job_requests[1])
         self.reserveNodesQuery = self.reserveNodesQuery.replace("$DEPTH$", job_requests[2])

         # Replace actual data for user, job ID and number of nodes to be
         # reserved in XML query string
         self.reserveNodesQuery = self.reserveNodesQuery.replace("$USERNAME$", cli.user)
         self.reserveNodesQuery = self.reserveNodesQuery.replace("$BATCHID$", cli.jobid)

      # ------------------------------
      # BASIL 1.0 RESERVATION confirmation
      # ------------------------------
      self.confirmResQuery = '''<?xml version="1.0"?>
<BasilRequest protocol="1.0" method="CONFIRM" job_name="$SGEJOBTASKID$" reservation_id="$RESERVATIONID$" admin_cookie="$SESSIONID$"/>'''

      # Replace actual data for reservation ID to be confirmed, admin cookie
      # and job ID in XML query string
      self.confirmResQuery = self.confirmResQuery.replace("$SESSIONID$", cli.adminCookie)
      self.confirmResQuery = self.confirmResQuery.replace("$SGEJOBTASKID$", cli.jobid)
      if clioptset("confirmRes"):
         # Won't need this query otherwise
         self.confirmResQuery = self.confirmResQuery.replace("$RESERVATIONID$", getReservationID())

      # ------------------------------
      # BASIL 1.0 Reservation Cancellation
      # ------------------------------
      self.cancelResQuery = '''<?xml version="1.0"?>
<BasilRequest protocol="1.0" method="RELEASE" reservation_id="$RESERVATIONID$"/>'''

      # Replace actual data for reservation ID to be cancelled in XML query string
      if clioptset("cancelRes"):
         # Won't need this query otherwise
         self.cancelResQuery = self.cancelResQuery.replace("$RESERVATIONID$", getReservationID())

   def handleQuery(self):
      """
      Execute the query and process plus print the results
      """
      # Query XML string and parsing option based on keyopt (set in CLI())
      p = feedNreadBASIL(getattr(self, keyopt + "Query"), keyopt)

      if p.returnStatus == "SUCCESS":
         # Print return value as defined in cliFlags and stored in parser
         # object
         print getattr(p, "return" + cliFlags[keyopt][optrettype])
      else:
         # Extra error output information in case of detecting inhomogeneous
         # segment and processor counts during the --nodes query
         if cli.nodes:
            sys.stderr.write(getattr(p, "return" + cliFlags[keyopt][optrettype]))
         # Output the message defined in cliFlags for this option plus the
         # return status from the query in case of an error
         errExit(1, cliFlags[keyopt][opterrmsg] + " Returned status: " + p.returnStatus)

def parseRUR(filename):
   """
   Parses a given file for accounting records in RUR style and
   prints the values space separated on stdout.
   """

   def grepNum(li, key):
      """
      Grep values directly following key string from a list & convert to int.
      """
      if key not in li:
         # gets added up so by return 0 nothing changes if key is not there
         return 0
      try:
         num = li[1+li.index(key)]   # the elem after the one matching 'key'
      except:
         # should only happen of the +1-index is out of range in the list
         errExit(13, "Element >>" + key + "<< in RUR accounting doesn't " \
            + "seem to have a succeeding value element.")
      if num.isdigit():
         return int(num)
      else:
         errExit(13, "Value element for >>" + key + "<< in RUR accounting " \
            + "is expected to be an int but was >>" + num + "<<.")

   # Check if filename is a valid file and open it
   try:
      f = open(filename, 'r')
   except:
      errExit(12, "Error opening filename (" + filename +") for reading")

   # This is the line format going to to be parsed:
   # uid: 1000, apid: 8410, jobid: 0, cmdname: /tmp/dostuff taskstats ['utime', 32000, 
   # 'stime', 132000, 'max_rss', 1736, 'rchar', 44524, 'wchar', 289] 
   # uid: 1000, apid: 8410, jobid: 0, cmdname: /tmp/dostuff energy ['energy_used', 24551] 
   # uid: 1000, apid: 8410, jobid: 0, cmdname: /tmp/dostuff gpustats ['maxmem', 108000, 
   # 'summem', 108000
   utime = 0
   stime = 0
   max_rss = 0
   rchar = 0
   wchar = 0
   # in case only rss is shown
   rss = 0

   for line in f:
      # Only handle "taskstats" accounting line 
      if "taskstats" not in line:
         continue

      stats = re.match(r"[^\[]*\[(.*)\][^\]]*", line).group(1)
         # extracts the part inside the 1st [ and the last ]
      stats = stats.replace(" ","").replace("'","")
         # remove blanks and ticks
      statl = stats.split(",")   # convert to list

      # Add up values from consecutive taskstats lines
      utime += grepNum(statl, "utime")
      stime += grepNum(statl, "stime")
      rchar += grepNum(statl, "rchar")
      wchar += grepNum(statl, "wchar")

      # Find maximum from consecutive taskstats lines for resident set size
      # elements
      max_rss = max(max_rss, grepNum(statl, "max_rss"))
      rss = max(rss, grepNum(statl, "rss"))

   # Make sure max_rss reflects real maximum
   if rss > max_rss:
      max_rss = rss

   # Convert microseconds to seconds, the remaining values are reported in RUR format
   if utime > 0:
      utime = utime / float(1000000)
   if stime > 0:
      stime = stime / float(1000000)

   print "%.3f" % utime + " " + "%.3f" %stime + " " + str(max_rss) + " " + str(rchar) + " " + str(wchar) + " "

def expandTaskIds(taskid):
   """
   Returns a list of task IDs specified by the task ID generator (1-100:2 for example)
   """
   if taskid == '' or '-' not in taskid or ':' not in taskid:
       return [ ]
   col = taskid.split(':')
   if len(col) != 2:
       return [ ]
   stepsize = int(col[1])
   jobrange = col[0].split('-')
   if len(jobrange) != 2:
       return [ ]
   return range(int(jobrange[0]), int(jobrange[1]), stepsize)

def getActiveJobs():
   """
   Get all job ids of jobs and array job tasks currently in Univa Grid Engine
   """
   ge = GridEngine()
   # require all array job tasks
   so = ge.qstat(['-u', '*', '-j', '*'])
   # job ids are collected as jobid.taskid - for non array
   # jobs jobid.1
   jobids = [ ]
   lines = so.split('\n')
   jobid = ''
   taskid = ''
   for line in lines:
      if "job_number:" in line:
          pair = line.split()
          if len(pair) == 2:
              jobid = pair[1]
      if "job-array tasks: " in line:
          triple = line.split()
          if len(triple) == 3:
              taskid = triple[2]
      if "scheduling info:" in line:
          # this is the last entry (even when turned off)
         if jobid != '':
            if taskid == '':
                jobids.append(jobid)
            else:
                # 1-100:1 for example
                for task in expandTaskIds(taskid):
                   jobids.append(jobid + "." + str(task))
         jobid = ''
         taskid = ''

   return jobids

def getJobWithReservations():
   """
   Returns a map of job ids (with task IDs when given: jobid.taskid) to Cray reservations.
   """
   apstat = distutils.spawn.find_executable("apstat")
   if not apstat:
      print "apstat application not found"
      sys.exit(14)
   jobAndReservation = {}
   try:
      p = subprocess.Popen([apstat, '-r', '-v'], stdout=subprocess.PIPE)
      out,err = p.communicate()
   except:
      errExit(14, "got exception while invoking apstat -r: " + err)

    # output:
    # $ apstat -r -v
    #  ResId    ApId From         Arch PEs N d Memory State  
    #   190 230Sec. batch:102757   XT   2 2 2   1024 unbound
    #   191 232Sec. batch:102757   XT   2 2 2   1024 unbound
    #   192 233Sec. batch:102757   XT   2 2 2   1024 unbound
    #
    # Reservation detail
    # Res[0]: apid 295, pagg 0, resId 190, user sgetest,
    #      gid 9901, account 9901, time 0, normal
    # Batch System ID = 102757.2
    # Reservation flags = 0x200 (exclusive)

   resID = ''
   jobID = ''
   skip = True
   lines = out.split('\n')
   for line in lines:
      if skip == True and "Reservation detail" not in line:
         continue
      skip = False
      if "resId " in line:
         numberRest = line.split('resId ')
         if len(numberRest) >= 1:
            nums = numberRest[1].split(',')
            if len(nums) >= 1:
               resID = nums[0]
      if "Batch System ID" in line:
          ids = line.split(" = ")
          if len(ids) == 2:
              jobID = ids[1]
      if resID != '' and jobID != '':
          jobAndReservation[jobID] = resID
          resID = ''
          jobID = ''
   return jobAndReservation

def orphanedReservations():
   """
   Returns a list of reservations which have no active Univa Grid Engine job
   """
   activeJobs = getActiveJobs()
   # that is our result
   orphanedReservations = [ ]

   jobmap = getJobWithReservations()
   activeJobsDict = dict((key, key) for key in activeJobs)
   # job IDs from apstat -r contain only job ID without task ID
   for jobid in jobmap:
      if jobid in activeJobsDict:
         # reservation is an active jobs
         continue
      else:
         # orphaned reservation! no active jobs for that
         orphanedReservations.append(jobmap[jobid])

   return orphanedReservations

# Main program
if __name__ == '__main__':
   # Do CLI parsing first
   CLI()

   # Check for non-XML requests
   if cli.sessionId:
      print os.getsid(0)
   elif cli.createAdminCookie:
      print getAdminCookie()
   elif clioptset("rur"):
      parseRUR(cli.rur)
   elif clioptset("jobs"):
      print getJobWithReservations()
   elif clioptset("orphanedReservations"):
      reservations = orphanedReservations()
      if len(reservations) == 0:
         sys.exit(15)
      print " ".join(reservations)
   else:
      # Now initialize the XML query object and do the XML query
      q = BasilQuery()
      q.handleQuery()
