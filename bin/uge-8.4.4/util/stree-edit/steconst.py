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

# These are definitions of constants for stree-edit.py

## Button and column labels
# The title string
STREEGUI_LBL = 'Univa Grid Engine Share-Tree Editor'
# Node modification button labels
ADD_NODE_LBL = 'Add Inner Node'
ADD_USER_LBL = 'Add User Leaf'
ADD_PROJ_LBL = 'Add Proj Node'
DEL_NODE_LBL = 'Delete Node'
# Buttons for persisting state and quitting the app
SAVE_LBL = 'Save'
RESTORE_LBL = 'Reload'
QUIT_LBL = 'Quit'
# Message box button labels
OK_LBL = 'OK'
CANCEL_LBL = 'Cancel'
# TreeView column labels
PIXCOL_LBL = ''
NAMESCOL_LBL = 'Names'
SHARESCOL_LBL = 'Shares'
TYPECOL_LBL = 'Type'
LEVELPRCTGCOL_LBL = 'Level %'
TOTALPRCTGCOL_LBL = 'Total %'
ACTSHARECOL_LBL = 'Actual Share'
LTGTSHARECOL_LBL = 'Long Target Share'
STGTSHARECOL_LBL = 'Short Target Share'
USGCOL_LBL = 'Comb. Usage'

## Font Description String for Title Label
TITLE_FONT = 'Arial 20'

## Integer Constanst
# Timeout (in milliseconds) for automatically refreshing the share-mon info
# Automatic refreshing will be discontinued while edits of the share-tree are
# unsaved
RECALC_TIMEOUT = 30000
# Mininum and default window sizes
MIN_WIDTH = 500
MIN_HEIGHT = 300
DEFAULT_WIDTH = 850
DEFAULT_HEIGHT = 500
HELP_WIDTH = 500
HELP_HEIGHT = 500

## Path and environment variable related strings
GE_ENV_PREFIX='SGE_'
LO_ENV_PREFIX='ULO_'
GE_ARCH_SCR='arch'
LO_ARCH_SCR='arch'
GE_SHARE_MON='sge_share_mon'
LO_SHARE_MON='lo_share_mon'
GE_CONF='qconf'
LO_CONF='loconf'
ICON_SUBDIR = 'icons'
UGE_LOGO = 'grid_engine_logo.jpg'
UNIVA_LOGO = 'univa.png'

## A default share-tree is necessary if none was previously configured on
## start-up
# The default share-tree; consists of a root node and the default project
# underneath. Format is compliant with the one parsed from qconf -sstree
default_stree = ['id=0', 'name=root', 'type=0', 'shares=100',
    'childnodes=1', 'id=1', 'name=default', 'type=1', 'shares=100',
    'childnodes=NONE', '']
# Message to be printed when we create the share-tree
DEFAULT_STREE_MSG = ("""
Apparently no share-tree configured yet. Creating a default share-tree and
saving it. If not desired then quit and remove with 'qconf -dstree'.
""")

## The text of the "About" menu item under the "Help" pulldown
ABOUT_MSG = ( """
This tool and its associated code is the Property, a Trade Secret and the
Confidential Information\n of Univa Corporation.

Copyright Univa Corporation. All Rights Reserved. Access is Restricted.

It is provided to you under the terms of the Univa Term Software License
Agreement.

If you have any questions, please contact our Support Department.

www.univa.com""")

## The text of the "Help" menu item under the "Help" pulldown
HELP_MSG = ("""
View and modify share-trees. Monitor how the resource consumption from
running jobs influences the automatic fair-share entitlement management.

Select share-tree nodes by clicking on them. Only one share-tree node can
be selected at any time. Use the buttons to the upper right or the
correspondig items under the Edit pulldown menu to add different types of
nodes or to delete nodes. You can also drag and drop nodes to move nodes
and their sub-trees within the share-tree.

Upon editing nodes you will need to enter the name of the node and the
associated shares. Project and user names being added need to be known
to the system. If they are not known at the time of attempting to add them
you will be prompted to decide whether those projects/users should be
added automatically.

When the share-tree gets manipulated then the columns Level % and Total %
will get updated. The rest of the columns gets invalidated until the
changes have been saved or the share-tree gets reloaded.

The meaning of the columns is:

   Names:
       The names of the share-tree nodes.
   Shares:
       The shares associated with the share-tree node.
   Level %:
       The entitlement percentage based on the shares of all nodes at the
       same level in the sub-tree of this node.
   Total %:
       The entitlement percentage for this node based on all shares of all
       nodes in the share-tree.
   Actual Share:
       The actual share entitlement the node has received based on the
       past resource usage when compared to all nodes.
   Long Target Share:
       A longer term share target by which the system tries to accomplish
       an actual share entitlement close to what is defined in Shares.
   Short Targer Share:
       A shorter term share target by which the system tries to accomplish
       an actual share entitlement close to what is defined in Shares.
   Comb. Usage:
       The past resource usage being accrued for the node thus far.

All columns except for Names and Shares will be updated periodically unless
the share-tree has unsaved changes. The interval in which the updates occur
can be set via the --refresh-interval command-line option. Use a value of 0
to turn off automatic updating. Use the --help option for more information
on command-line options for this program.

Use the Save, Reload and Quit buttons on the right or the corresponding
items in the File pulldown menu to save changes, reload the share-tree for
overwriting previous changes or to quit the application."
""")
