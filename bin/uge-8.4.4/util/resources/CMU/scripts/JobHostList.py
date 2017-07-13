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
Prints one line per job containing all hosts the job is running on in the format:
   <jobId> [<hostname>] ...
So for instance:
   13.1 host1 host2 host3
   77 host1
Parses output from 'qhost -j -xml' to create that output
"""

import subprocess
import sys
import xml.parsers.expat

def addHostToJob(d, h, j):
   """
   Helper function updating a dictionary with set elements. Adds a new set
   if key is not present and adds element to the set-value of the key.
   Make sure that h (host) is always short host name (split at '.').
   """
   
   if j not in d:
      d[j] = set()
   d[j].add(h.split(".")[0])

def run_cmd(cmd):
   """"
   Embedds running command via subprocess.check_output with some error
   handling. Input paramter 'cmd' is commandline string including all
   arguments.
   """
   cmdl = cmd.split(" ")
   try:
      p = subprocess.Popen(cmdl, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      so, se = p.communicate()
   except subprocess.CalledProcessError, e:
      sys.stderr.write("Error encountered in running '" + cmd +
         "'. Return status is '" + str(e.returncode) + "'\n")
      sys.exit(1)
   except:
      sys.stderr.write("Unknown error encountered in running 'qhost -j -xml'.\n")
      sys.exit(1)
   return so

class parseXML(object):
   def __init__(self, xmldoc):
      """
      Uses the expat parser from the xml module
      """
      # Define and preset variables used across the expat parser functions
      self.jobID = ""         # stores the ID of the job element being parsed
      self.taskID = False     # indicates whether taskid field got detected which has a
                              # task ID in the character data field of that XML element
      self.arrayJob = False   # indicates whether we are dealing with an array job
      self.host_dict = dict() # stores the job-->hostlist map in a dictionary
      self.current_host = ""  # contains the host element currently being parsed

      # Now create expat parser
      p = xml.parsers.expat.ParserCreate()
      # Assign handler for XML element starts; handler name is based on
      # key option (method object retrieved with getattr)
      p.StartElementHandler = self.__startElem
      # End elem handler
      p.EndElementHandler = self.__endElem
      # Character Data Handler
      p.CharacterDataHandler = self.__charData
      # Parse the doc
      p.Parse(xmldoc)

      # Finally print the dictionary.
      for k,v in self.host_dict.items():
         print k + " " + " ".join(list(v))

   def __startElem(self, name, attrs):
      """
      invoked whenever the parser enters into an element
      """
      if name == "host" and attrs["name"] <> "global":
         # We skip the 'global' host. Otherwise we set the
         # host name for all following jobs.
         self.current_host = attrs["name"]
      elif name == "job":
         if self.jobID <> attrs["name"]:
            # If a job element with a new job ID starts then we need to reset
            # to array job indicator.
            self.arrayJob = False
         # Store job ID for later use in __endElem and __charData
         self.jobID = attrs["name"]
         
      elif name == "jobvalue" and attrs["name"] == "taskid":
         # If we have detected a jobvalue element with a taskid attribute then
         # we know this is an array job and we need use __charData to parse out
         # the task ID. Set flags for both.
         self.taskID = True
         self.arrayJob = True

   def __endElem(self, name):
      """
      invoked whenever the parser sees the end specifier for an element
      """
      if name == "job" and not self.arrayJob:
         # When job elements finish for non-array jobs then just 
         # append the host to the job.
         addHostToJob(self.host_dict, self.current_host, self.jobID)

   def __charData(self, data):
      """
      invoked whenever the parser sees character data field, e.g. the 't' in
      <p>'t'</p>
      """
      if self.taskID:
         # We only take character data fields into account for jobvalue
         # elements with a taskid attribute. taskID indicates this and gets
         # set in __startElem if defined for a job element.
         # Adding array job with <jobid>_<taskid> to the dictionary
         addHostToJob(self.host_dict, self.current_host, self.jobID + "_" + data)
         # Reset task ID.
         self.taskID = False

# Main program
if __name__ == '__main__':
   # Get xml output from "qhost -j -xml"
   xmldoc = run_cmd("qhost -j -xml")
   # Parse it and print out job IDs and task IDs per host on the fly
   parseXML(xmldoc)
