#!/usr/bin/python -u
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

import os
import sys
import subprocess
import tempfile
import pygtk
pygtk.require('2.0')
import gtk
import pango
import gobject
from optparse import OptionParser
from gridengine import GridEngine

def Usage():
    """
    Function which performs command-line parsing checks. Returns True if no
    errors are encountered and False otherwise.
    """

    # options will receive the command-line options from the parser. Make it
    # global to have them available where needed
    global options
    

    # Create the parser and add the currently supported options
    parser = OptionParser()

    # Switch which keeps the temp files which are use for qconf -M*
    # commands (mostly for debugging).  Also this only works with 2.6+
    if sys.version_info >= (2, 6):
        parser.add_option("--keep-tempfile",
            action="store_true", dest="keep_tmpfiles", default=False,
            help="Keep temporary files (for debugging).")

    # Set the window size
    parser.add_option("--window-size",
        action="store", dest="wsize", type="str",
        default=str(C.DEFAULT_WIDTH) + 'x' + str(C.DEFAULT_HEIGHT),
        help="Set window size. [Default: %default]")

    # Set the auto-update interval for monitoring through share-mon. Setting
    # it to 0 turns refreshing off.
    parser.add_option("--refresh-interval",
        action="store", dest="interval", type="int",
        default=str(C.RECALC_TIMEOUT/1000),
        help="Interval for refreshing monitoring info in seconds.\n" +
        "Use 0 to turn off refreshing. [Default: %default]")

    # Select whether this is UGE or LO in case the app can't guess which one
    # to talk to.
    parser.add_option("--product",
        action="store", dest="product", type="str", default="none",
        help="Select product interfacing with {sge|lo}.")

    # Parse for command-line arguments
    (options, args) = parser.parse_args()

    # Checking for validity of product selector (if specified; otherwise
    # default of 'none' applies)
    if not options.product == 'none':
        if not options.product == 'sge' and not options.product == 'lo':
            print "Error: either product sge or lo needs to be selected"
            parser.print_usage()
            return False

    # Checking of validity of window size option
    szvalid = True
    numsz = 0
    # Format is WIDTHxHEIGHT with WIDTH and HEIGHT being int
    size = options.wsize.split('x')
    if len(size) !=2 or not size[0].isdigit() or not size[1].isdigit() or \
            int(size[0]) < 0 or int(size[1]) < 0:
        print "Error: window size must be WIDTHxHEIGHT; WIDTH/HEIGHT must be integer > 0"
        parser.print_usage()
        return False

    # We also have min width and height. Set them if needed.
    if int(size[0]) < C.MIN_WIDTH:
        print 'Window width too small; setting to minimum %i' % C.MIN_WIDTH
        size[0] = str(C.MIN_WIDTH)
    if int(size[1]) < C.MIN_HEIGHT:
        print 'Window height too small; setting to minimum %i' % C.MIN_HEIGHT
        size[1] = str(C.MIN_HEIGHT)
    options.wsize = size[0] + 'x' + size[1]

    # The refresh interval also needs to be at least 0 (means refresh is
    # turned off)
    if int(options.interval) < 0:
        print "Error: refresh interval needs to be >= 0."
        parser.print_usage()
        return False

    # The 'delete' keyword in NamedTemporaryFile is not support on pre2.6 so exclude the argument
    # if we are using the default parameter of True which is always the case in 2.4
    if hasattr(options, 'keep_tmpfiles'):
        options.named_temp_file_args = {'delete': (not options.keep_tmpfiles) }
    else:
        options.named_temp_file_args = {}

    return True

def fwrite_share_tree(stree_out_list):
    # Print out share tree info in qconf -Mstree format;
    # the correct format has already been put into stree_out_list
    # Print to tempfile, then run qconf -Mstree
    tf = tempfile.NamedTemporaryFile(**options.named_temp_file_args)
    # print tf.name
    stree_out = '\n'.join(stree_out_list)
    tf.write(stree_out)
    tf.flush()
    return uge.run_cmd([uge.qconf,'-Mstree',tf.name])

class ShareTree(object):
    """
    Class containing share tree specific methods.
    Main procedures are fill and fwrite.
    fill is for filling share tree info from the qconf -sstree output into
    a gtk.TreeStore which is then displayed via a gtk.TreeView
    fwrite is for dumping out the share tree model in the gtk.TreeStore in
    qconf -Mstree compliant format and then run qconf to change the share
    tree.
    The other methods are helper methods.
    """

    def __init__(self):
        """
        Class is just container for share tree related procedures
        and the XPM Pixmaps for user/project leaf nodes and inner nodes
        """
        iconpath = os.path.dirname(sys.argv[0]) + '/' + C.ICON_SUBDIR + '/'
        self.userpb=gtk.gdk.pixbuf_new_from_file(iconpath + 'user.xpm')
        self.projpb=gtk.gdk.pixbuf_new_from_file(iconpath + 'proj.xpm')
        self.fldrpb=gtk.gdk.pixbuf_new_from_file(iconpath + 'folder.xpm')
        return

    def fwrite(self, ts):
        """
        Write the share-tree to a file compliant for qconf -Mstree.
        Then run qconf -Mstree to register the changes with UGE
        The method creates the temp file being used.
        The information to be written gets extracted from the treestore being
        passed as argument ts.
        """

        # For checking on --keep-file command-line option when we create the
        # temp file
        global options

        # The -Mstree format requires consecutive numbering of share-tree
        # nodes. With __dump_stree we traverse recursively through the
        # treestore. While doing that, the below variable is used to
        # maintain the node count. Preset to 0 for initial run.
        self.stree_idx=0

        # Count share-tree nodes and allocate string list for output
        # There are 5 lines in the output per node:
        #    id,name,type,shares,childnodes
        self.stree_out_list=[None] * self.__count_tree_nodes(ts) * 5

        # Dump share tree info into street_out_list
        self.__dump_stree(ts, 0)

        # Print out share tree info in qconf -Mstree format;
        # the correct format has already been put into stree_out_list
        # Print to tempfile, then run qconf -Mstree
        """
        tf = tempfile.NamedTemporaryFile(**options.named_temp_file_args)
        tf
        self.stree_out_list = '\n'.join(self.stree_out_list)
        tf.write(self.stree_out_list)
        tf.flush()
        so,se,err = uge.run_cmd([uge.qconf,'-Mstree',tf.name])
        """
        so,se,err = fwrite_share_tree(self.stree_out_list)
        if not so == '' or not se == '':
            MsgBox.label.set_text(so+se)
            MsgBox.window.show_all()
        if err != 0:
            return False
        else:
            return True

    def fill(self, ts, qconf_stree, index=0, parent=None):
        """
        This method fills a gtk.TreeStore with share tree info contained in
        qconf_stree (which got initialized with qconf -sstree info at
        the program start or when the 'Reload' button has been pressed).
        ts points to the treestore we are going to fill with the share tree
        information.
        This is a recursive procedure and the 1st argument index points to the
        location in the "flat" qconf_stree format where the 5 lines
        representing the node to be processed resides. Default of 0 means the
        first record in the qconf -stree output.
        parent is the iter from which we've entered into this method. Default
        of None means no node has been created previously.
        """

        # index points to the block of 5 records in qconf_stree_output
        # which defines the share tree node we deal with here
        spec,self.id       = qconf_stree[index].split('=')
        spec,self.name     = qconf_stree[index+1].split('=')
        spec,self.type     = qconf_stree[index+2].split('=')
        spec,self.shares   = qconf_stree[index+3].split('=')
        spec,children_list = qconf_stree[index+4].split('=')
        self.children = children_list.split(',')

        if self.type == '1':
            # type=1 means it's a project node
            pb = self.projpb
        else:
            if children_list == 'NONE':
               # This is a user node
               pb = self.userpb
            else:
               # This is an inner node
               pb = self.fldrpb

        # Add this share tree node to the treestore
        # row contents are: icon, name, shares, lvl %, total %, act share,
        #     long tgt share, short tgt share, comb. usg, type
        # The return value is the Iter identifier for this node
        iter=ts.append(parent,[pb,self.name,self.shares,'--',
                               '--','--','--','--','--',self.type])
        # If this node has children then branch the recursion to them
        # The ID of the child node determines the index in the qconf output
        # Pass the Iter of the parent. We need it for TreeStore.append
        for child in self.children:
            if child != 'NONE':
                self.fill(ts, qconf_stree, int(child)*5, iter)

    def invalidate_share_mon_info(self, ts, p):
        """
        Invalidate the share-mon info in a subtree by setting the
        corresponding values to '--'
        ts is the treestore which we are updating.
        p is pointing to the node from which the subtree spans which needs to
        be updated.
        """

        # Copy the values which remain valid; set '--' for the rest
        # The valid items are icon, name, shares, level & total % and type
        node_data = [ ts.get_value(p,0), ts.get_value(p,1), ts.get_value(p,2),
                      ts.get_value(p,3), ts.get_value(p,4), '--', '--',
                      '--', '--', ts.get_value(p,9) ]
        for n in range(0, len(node_data)):
            ts.set_value(p, n, node_data[n])

        # Walk through the subtree recursively
        c = ts.iter_children(p)
        while c:
            self.invalidate_share_mon_info(ts, c)
            c = ts.iter_next(c)
        
    def recalc_percentages(self, ts, p):
        """
        Recalculate the level percentage and the total percentage within a
        subtree of the share tree.
        This method is supposed to be called when a new node has been added
        or a node has been deleted or a subtree has been moved
        ts is the treestore which we are updating.
        p is pointing to the node from which the subtree spans which needs to
        be updated.
        """

        # The total percentage as stored in the parent
        p_total_prctg = float(ts.get_value(p, 4))/100

        # We'll need two passes - one to calculate the new total shares at
        # that level, the other to calculate the level and total percentages

        # Pass 1: calculate the total shares at this level
        level_total = 0
        c = ts.iter_children(p)
        while c:
            level_total += int(ts.get_value(c, 2))
            c = ts.iter_next(c)

        # Pass 2: calculate the total and level percentages
        c = ts.iter_children(p)
        while c:
            level_prctg = float(ts.get_value(c, 2))/float(level_total)
            # The level percentage
            ts.set_value(c, 3, "%0.2f" % (level_prctg*100))
            # The total percentage
            ts.set_value(c, 4,
                "%0.2f" % (p_total_prctg*level_prctg*100))
            # Step down one recursion
            self.recalc_percentages(ts, c)
            c = ts.iter_next(c)
        
        return True

    def fullcopy(self, tssrc):
        """
        Copy treestore passed as argument into newly created gtk.TreeStore
        object which is returned. Uses copy_sub method for recursion and,
        for debugging, a foreach iteration with the print_cb callback.

        (Had tried to use deepcopy from the copy module but it doesn't seem
        to work for GObjects. So I've written this function.)
        """
        tsdest = gtk.TreeStore(gtk.gdk.Pixbuf, str, str, str, str, str, str,
                               str, str, str)
        self.__copy_sub(tssrc, tssrc.get_iter_first(),
                      tsdest, tsdest.get_iter_first())
        # print '-----------'
        # tssrc.foreach(self.__print_cb, tssrc)
        # print '-----------'
        # tsdest.foreach(self.__print_cb, tsdest)
        return tsdest

    def __copy_sub(self, tssrc, itersrc, tsdest, iterdest):
        """
        Recursion to copy subtrees from TreeStore.
        tssrc is the source treestore from which to make copy and itersrc
        points to the subtree we want to copy.
        tsdest is the destination treestore into which we are copying and
        iterdest is pointing to the subtree there.
        """
        iterdest = tsdest.append(iterdest, tssrc[tssrc.get_path(itersrc)])
        c = tssrc.iter_children(itersrc)
        while c:
            self.__copy_sub(tssrc, c, tsdest, iterdest)
            c = tssrc.iter_next(c)

    def print_stree(self, model):
        model.foreach(self.__print_cb, model)

    def __print_cb(self, model, path, iter, ts):
        """
        Call-back function used in foreach iteration to print treestores for
        debugging purposes.
        the 'model' argument is unused but required by the callback format.
        path is the path to the node in gtk.TreeStore path format.
        iter points to the same node but is an iter.
        ts is the treestore.
        """
        print path
        print ts.get_value(iter, 1)
        return False

    def __count_node_cb(self, model, path, iter, user_data):
        """
        Call-back function used in foreach iteration in count_tree_nodes
        None of the arguments are being used. They are required by the
        callback format.
        """
        self.numnodes += 1
        return False

    def __count_tree_nodes(self, ts):
        """
        Count the nodes in the tree so we can allocate string lists
        containing the output we want to dump to file. ts is the treestore.
        """
        self.numnodes=0
        ts.foreach(self.__count_node_cb,self.numnodes)
        return self.numnodes

    def __dump_stree(self, ts, path):
        """
        Dump share tree from gtk.TreeStore into stree_out_list

        This is a somewhat complicated recursive methode because the
        hierarchical share tree info needs to get flattened into file format
        compliant for qconf -Mstree

        It might be possible to do this a bit simpler with a foreach
        iteration. Todo for later.

        ts is the treestore from which we dump.
        path is the path into the current node being processed.
        """

        # Safe index of this node so we can use it for printing out the
        # correct index number
        idx = self.stree_idx

        # Get iter reference for row in share tree
        iter = ts.get_iter(path)

        # Use stree_idx as id / idx*5 points to id-line for node in output
        self.stree_out_list[idx*5] = 'id=' + str(self.stree_idx)
        # increment for next node info to be printed
        self.stree_idx += 1

        # Dump name, type & shares ==> output lines are idx*5+1/2/3
        self.stree_out_list[idx*5+1] = 'name=' + ts[path][1]
        self.stree_out_list[idx*5+2] = 'type=' + ts[path][9]
        self.stree_out_list[idx*5+3] = 'shares=' + ts[path][2]

        # Handle child nodes if any
        childiter = ts.iter_children(iter)
        if childiter == None:
            # No children, so dump that / output line is idx*5+4
            self.stree_out_list[idx*5+4] = 'childnodes=NONE'
        else:
            # Traverse thru all children
            children = ''
            while childiter:
                # Create a comma separated string for printing
                if children == '':
                    children = str(self.stree_idx)
                else:
                    children = children + ',' + str(self.stree_idx)
                # Step down one recursion level into child node
                self.__dump_stree(ts, ts.get_path(childiter))
                childiter = ts.iter_next(childiter)

            # Dump children string
            self.stree_out_list[idx*5+4] = 'childnodes=' + children

class ShareNode(object):
    """
    Class representing the UGE share tree node as returned by sge_share_mon
    """

    def __init__(self,sge_share_mon_line=None, delim=','):
        super(ShareNode,self).__init__()
        # Constructor fills a data structure representing one node as returned
        # by sge_share_mon

        # Properties from the sge_share_mon '-h' output
        self.curr_time = ''
        self.usage_time = ''
        self.node_name = ''
        self.user_name = ''
        self.project_name = ''
        self.shares = ''
        self.job_count = ''
        self.level_percent = ''
        self.total_percent = ''
        self.long_target_share = ''
        self.short_target_share = ''
        self.actual_share = ''
        self.usage = ''
        self.cpu = ''
        self.mem = ''
        self.io = ''
        self.ltcpu = ''
        self.ltmem = ''
        self.ltio = ''

        # Non-UGE share_mon info
        self._level = 0
        self._children = []
        self._parent = None
        self._last = True

        # Parse the share-mon line into strings 
        if sge_share_mon_line:
            parts = sge_share_mon_line.split(delim)
            if len(parts)==20:
                # And store them into the data structure for this node
                self.curr_time, self.usage_time, self.node_name, self.user_name, self.project_name, self.shares, self.job_count, \
                  self.level_percent, self.total_percent, self.long_target_share, self.short_target_share, self.actual_share, self.usage, \
                  self.cpu, self.mem, self.io, self.ltcpu, self.ltmem, self.ltio,junk = parts

                # Update the level based on the node name
                self.__update_level()
            else:
                raise "Invalid sge_mon_line"

    def __update_level(self):
        """ The level is determined by the name """
        if self.node_name == '/':
            self._level = 0
        else:
            # Count the slashes
            self._level = self.node_name.count('/')

    def add_child(self,child):
        """ Add a child to the hierarchy """

        # share-mon displays nodes in a '/' delimited path
        parent_name = child.node_name.rsplit('/',1)[0]

        # If we don't have a parent in the child then make this node the parent...this should only happen on the root node
        if parent_name == '':
            parent_name = self.node_name

        # print "Parent of %s is %s" % (child.node_name, parent_name)

        # If we are the parent then add to our children
        if self.node_name == parent_name:
            child._parent = self
            self._children.append(child)

            # Only the last added sibling should be marked last ...
            # set the previous last one as no longer the last
            if len(self._children) > 1:
                self._children[-2]._last = False
        else:
            for p in self._children:
                p.add_child(child)

    def extract_node_data(self, ts, iter, f=sys.stdout, supress_default=True):
        """
        Get the data from the data structure we have built from the
        share-mon output and set it into our treestore model
        """
        p = self._parent

        # Those are the elements were are interested in ... in the right order
        # for our treeview
        node_data = [ self.level_percent, self.total_percent,
                      self.actual_share, self.long_target_share,
                      self.short_target_share, self.usage ]
        # Run through them and set them into the treestore corresponding to the
        # the right columns in our treestore
        for n in range(0, len(node_data)):
            ts.set_value(iter, n+3,
                "%0.2f" % (float(node_data[n])*100))

        # The share tree has 'internal' nodes under the special default nodes...hide those by default
        if not supress_default or not self.node_name.endswith('/default') :
            # Loop through all of the children printing out their info
            child = ts.iter_children(iter)
            for c in self._children:
                c.extract_node_data(ts, child, f,supress_default)
                child = ts.iter_next(child)

class ShareTreeView(object):
    """
    This is the GUI class for displaying the share tree and for the buttons
    to manipulate the share tree as well as for saving the tree, reloading
    it or quitting the app
    """

    def __init__(self):
        """ The TreeView GUI constructor """

        # From the command-line parser ... used here for setting the window
        # size
        global options

        # Preset string lists for column and button labels
        self.colnm = [ C.PIXCOL_LBL, C.NAMESCOL_LBL, C.SHARESCOL_LBL,
                       C.LEVELPRCTGCOL_LBL, C.TOTALPRCTGCOL_LBL,
                       C.ACTSHARECOL_LBL, C.LTGTSHARECOL_LBL,
                       C.STGTSHARECOL_LBL, C.USGCOL_LBL ]
        # The below is a subset of the above. Only the below are editable by
        # the user. It really only should be the names and the shares column
        # but it seems that columns need to be editable to be visible.
        self.colnm_editable = [ C.NAMESCOL_LBL, C.SHARESCOL_LBL,
                       C.LEVELPRCTGCOL_LBL, C.TOTALPRCTGCOL_LBL,
                       C.ACTSHARECOL_LBL, C.LTGTSHARECOL_LBL,
                       C.STGTSHARECOL_LBL, C.USGCOL_LBL ]
        self.add_del_btn_lbl = [ C.ADD_NODE_LBL, C.ADD_PROJ_LBL,
                                 C.ADD_USER_LBL, C.DEL_NODE_LBL ]
        self.persist_btn_lbl = [ C.SAVE_LBL, C.RESTORE_LBL, C.QUIT_LBL ]

        # Create a new window with the title string
        self.window = gtk.Window(gtk.WINDOW_TOPLEVEL)
        self.window.set_title(C.STREEGUI_LBL)

        # Set the window size; correctness of format of options.wsize has been
        # checked in the Usage method
        width, height = options.wsize.split('x')
        self.window.set_size_request(int(width), int(height))

        # Default delete event
        self.window.connect("delete_event", self.__delete_event)

        # In this window goes an area with icons at the top and underneath
        # that the main area with the share-tree view to the left and some
        # modifier buttons to the right.

        # First a vbox for the logo area at the top and then then main area
        # underneath
        topvbox = gtk.VBox()
        # Now the default menu bar with File / Edit and Help pulldowns
        self.__create_menu()
        menubar = self.__get_main_menu(self.window)
        # Now an hbox for the logos (left & right) and a title label in the
        # middle
        logohbox = gtk.HBox()
        # Now a hbox which will contain the share-tree on the left
        # and the buttons on the right
        mainhbox = gtk.HBox()
        # Now pack those three one on top of each other. The menu bar and the
        # logo-box will only consume space corresponding to their minimal
        # size (2nd arg = False), the main habox will take up the rest
        topvbox.pack_start(menubar, False, True, 0)
        topvbox.pack_start(logohbox, False)
        topvbox.pack_start(mainhbox, True)

        # Before we add the share-tree and the buttons let's first setup the
        # logo area at the top
        self.__create_logobox(logohbox)

        # Add 4 buttons - for adding inner/proj/user nodes & for deleting nodes
        # And Add 3 buttons - for saving, reloading and qutting
        # All buttons will go to the right of the share-tree view which is
        # contained in a scrolled window.
        # The 4 node modification buttons will go to the top at the right.
        # Then comes a separator and then the 3 buttons for persisting status
        # change.

        # We need a vbox for the two sets of buttons and a scrolled
        # windows for the share-tree window
        scrolledwindow = gtk.ScrolledWindow()
        btn_vbox = gtk.VBox()
        # Now stuff the scrolled window into the vbox
        mainhbox.pack_start(scrolledwindow, True)
        # And next to it the vbox for the button sets
        mainhbox.pack_end(btn_vbox, False)

        # Create button area to the right
        self.__create_btnbox(btn_vbox)

        # Create the TreeView using TreeStore as the model
        # It will get configured in the __create_treeview procedure and then
        # added to the scrolled window
        self.treeview = gtk.TreeView(TreeStore)
        self.__create_treeview(self.treeview)

        # Add the treeview to the scrolled window and the top vbox to
        # the parent window
        scrolledwindow.add(self.treeview)
        self.window.add(topvbox)

        # Open up with all nodes in the treeview being expanded
        self.treeview.expand_all()

        # Get TreeSelection and set selction mode to single rows only
        treeselection = self.treeview.get_selection()
        treeselection.set_mode(gtk.SELECTION_SINGLE)
        # Start without root node being selected
        treeselection.unselect_path(0)

        # Now let's show it all
        menubar.show()
        self.window.show_all()

    def reload(self):
        """
        Reload the tree from qconf -sstree
        Removes the content of the current TreeStore
        """
        # Get treestore model and remove it
        model = self.treeview.get_model()
        model.remove(model.get_iter_first())
        # Execute qconf -sstree and re-fill the TreeStore with it
        qconf_stree_output = ['']
        qconf_stree_output = uge.read_share_tree()
        STree.fill(model, qconf_stree_output)
        # Also get the monitoring data from sge_share_mon and start automatic
        # refreshing of it
        read_share_mon_info()
        ar.start()
        # Show with all nodes being expanded
        self.treeview.expand_all()

    def __create_logobox(self, logobox):
        """ Creates the area with logos and title label """

        # Create two image objects then load the images from file
        uge_logo = gtk.Image()
        univa_logo = gtk.Image()
        iconpath = os.path.dirname(sys.argv[0]) + '/' + C.ICON_SUBDIR + '/'
        uge_logo.set_from_file(iconpath + C.UGE_LOGO)
        univa_logo.set_from_file(iconpath + C.UNIVA_LOGO)
        # Also create a label object with appropriate text and font settings.
        title_label = gtk.Label(C.STREEGUI_LBL)
        font_desc = pango.FontDescription(C.TITLE_FONT)
        title_label.modify_font(font_desc)
        # And arrange them with the title label at the center
        logobox.pack_start(uge_logo, True)
        logobox.pack_start(title_label, True)
        logobox.pack_end(univa_logo, True)

        # This is supposed to set the background color in the logo-hbox to
        # white but it doesn't work. Either need to activate background color
        # rendering for the hbox or need some sort of container widget that
        # will render background colors. Let's leave it here as a placeholder
        # ... it doesn't hurt either.
        logobox.modify_fg(gtk.STATE_NORMAL,
            logobox.get_colormap().alloc_color('white'))

    def __create_btnbox(self, btnbox):
        """
        Create the button area on the right. 'btnbox' is the container
        into which the buttons are packed.
        """
        # Allocate space for the button objects
        add_del_btn = [None] * len(self.add_del_btn_lbl)
        persist_btn = [None] * len(self.persist_btn_lbl)

        # The buttons itself go into vbox objects
        node_mod_vbox = gtk.VButtonBox()   # for the 4 node mod buttons
        persist_vbox = gtk.VButtonBox()    # for the 3 status change btns

        # Now we add the two button sets and the separator in between to the
        # container box 'btnbox'.
        btnbox.pack_start(node_mod_vbox, False)
        self.__add_btn_vbox(node_mod_vbox, add_del_btn,
                            self.add_del_btn_lbl, self.__add_del_button_cb)
        separator = gtk.HSeparator()
        btnbox.pack_start(separator, False, True, 10)
        btnbox.pack_start(persist_vbox, False)
        self.__add_btn_vbox(persist_vbox, persist_btn,
                            self.persist_btn_lbl, self.__persist_button_cb)

    def __create_treeview(self, treeview):
        """ Creates the treeview area and attaches it to 'treeview' """

        # Allocate space for the column and cell objects
        tvcol = [None] * len(self.colnm)
        cell = [None] * len(self.colnm)

        # Let's create cell renderers first. A pixbuf renderer for column 0
        # and text renderers for all.
        iconcell = gtk.CellRendererPixbuf()
        for n in range(0, len(self.colnm)):
            cell[n] = gtk.CellRendererText()

        # Create the column with the pixbuf icons
        tvcol[0] = gtk.TreeViewColumn(self.colnm[0], iconcell, pixbuf=0)
        treeview.append_column(tvcol[0])

        # Create the rest of the columns and add them to the treeview
        for n in range(1, len(self.colnm)):
            tvcol[n] = gtk.TreeViewColumn(self.colnm[n])
            treeview.append_column(tvcol[n])
            tvcol[n].pack_start(cell[n], True)
            treeview.set_search_column(n)

        # Set specific columns as editable
        self.__set_editable(cell, tvcol)

        # Allow drag and drop reordering of rows
        treeview.set_reorderable(True)
        treeview.connect("drag_data_get", self.__drag_data_get_data)
        treeview.connect("drag_data_received", self.__drag_data_received_data)

    def __destroy_cb(self, *kw):
        """ Destroy callback to shutdown the app """
        gtk.main_quit()
        return

    def __delete_event(self, widget, event, data=None):
        """ close the window and quit """
        gtk.main_quit()
        return False

    def __get_main_menu(self, window):
        """
        Creates an empty standard menu from an item factory and add to 'window'
        Outside of this method we'll add the File, Edit, Help, etc pulldowns
        to it.
        """

        # Needs an accelerator group, so create that
        accel_group = gtk.AccelGroup()

        # Initialize item factory; 1st arg is one of
        # gtk.{MenuBar|Menu|OptionMenu}; 2nd arg is path to theat menu; 3rd
        # arg is the accelerator group we've just added.
        item_factory = gtk.ItemFactory(gtk.MenuBar, "<main>", accel_group)

        # Generate the menu items. Pass to the item factory the list of menu
        # items. The are being set in the create_menu method
        item_factory.create_items(self.menu_items)

        # Attach the new accelerator group to the window.
        window.add_accel_group(accel_group)

        # keep a reference to item_factory to prevent its destruction
        self.item_factory = item_factory

        # Return the actual menu bar created by the item factory so we can add
        # it to the top level window
        return item_factory.get_widget("<main>")

    def __create_menu(self):
        """
        This method just sets the menu_item srtucture compliant with an
        ItemFactory.
        """
        # It has the following format:
        # Item 1: The menu path. The letter after the underscore indicates an
        #         accelerator key once the menu is open.
        # Item 2: The accelerator key for the entry
        # Item 3: The callback.
        # Item 4: The callback action. Use the default of 0
        #         which the callback is called.  The default is 0.
        # Item 5: The item type, used to define what kind of an item it is.
        #       Here are the possible values:

        #       None               -> "<Item>"
        #       NULL               -> "<Item>"
        #       ""                 -> "<Item>"
        #       "<Title>"          -> create a title item
        #       "<Item>"           -> create a simple item
        #       "<CheckItem>"      -> create a check item
        #       "<ToggleItem>"     -> create a toggle item
        #       "<RadioItem>"      -> create a radio item
        #       <path>             -> path of a radio item to link against
        #       "<Separator>"      -> create a separator
        #       "<Branch>"         -> create an item to hold sub items (optional)
        #       "<LastBranch>"     -> create a right justified branch 

        self.menu_items = (
            ( "/_File",         None,         None,               0, "<Branch>" ),
            ( "/File/_Save",    "<control>S", self.__save_cb,     0, None ),
            ( "/File/_Reload",  "<control>R", self.__restore_cb,  0, None ),
            ( "/File/",         None,         None,               0, "<Separator>" ),
            ( "/File/_Quit",    "<control>Q", self.__quit_cb,     0, None ),
            ( "/_Edit",         None,         None,               0, "<Branch>" ),
            ( "/Edit/Add _Inner Node",
                                "<control>I", self.__add_node_cb, 0, None),
            ( "/Edit/Add _Project Node",
                                "<control>P", self.__add_proj_cb, 0, None ),
            ( "/Edit/Add _User Leaf",
                                "<control>U", self.__add_user_cb, 0, None),
            ( "/Edit/",         None,         None,               0, "<Separator>" ),
            ( "/Edit/_Delete Node",
                                "<control>D", self.__del_node_cb, 0, None ),
            ( "/_Help",         None,         None,               0, "<LastBranch>" ),
            ( "/_Help/_About",  "<control>A", self.__about_cb,    0, None ),
            ( "/_Help/_Help",   "<control>H", self.__help_cb,     0, None ),
            )

    def __help_cb(self, widget, data):
        HelpBox.window.show_all()

    def __about_cb(self, widget, data):
        AboutBox.window.show_all()

    def __save_cb(self, widget, data):
        """ Callback used in Menu ==> segway over to persist btn callback """
        self.__persist_button_cb(None, self.persist_btn_lbl.index(C.SAVE_LBL))

    def __restore_cb(self, widget, data):
        """ Callback used in Menu ==> segway over to persist btn callback """
        self.__persist_button_cb(None, self.persist_btn_lbl.index(C.RESTORE_LBL))

    def __quit_cb(self, widget, data):
        """ Callback used in Menu ==> segway over to persist btn callback """
        self.__persist_button_cb(None, self.persist_btn_lbl.index(C.QUIT_LBL))

    def __persist_button_cb(self, widget, n):
        """
        Call-back handling the buttons used for persisting status, i.e. the
        save, reload and quit buttons
        """
        if self.persist_btn_lbl[n] == C.SAVE_LBL:
            # Save the tree ==> qconf -Mstree
            if STree.fwrite(self.treeview.get_model()):
                read_share_mon_info()
                ar.start()
        elif self.persist_btn_lbl[n] == C.RESTORE_LBL:
            STreeView.reload()
        else:
            # This is the C.QUIT_LBL case
            gtk.main_quit()

    def __add_node_cb(self, widget, data):
        """ Callback used in Menu ==> segway over to add/del btn callback """
        self.__add_del_button_cb(None, self.add_del_btn_lbl.index(C.ADD_NODE_LBL))

    def __add_proj_cb(self, widget, data):
        """ Callback used in Menu ==> segway over to add/del btn callback """
        self.__add_del_button_cb(None, self.add_del_btn_lbl.index(C.ADD_PROJ_LBL))

    def __add_user_cb(self, widget, data):
        """ Callback used in Menu ==> segway over to add/del btn callback """
        self.__add_del_button_cb(None, self.add_del_btn_lbl.index(C.ADD_USER_LBL))

    def __del_node_cb(self, widget, data):
        """ Callback used in Menu ==> segway over to add/del btn callback """
        self.__add_del_button_cb(None, self.add_del_btn_lbl.index(C.DEL_NODE_LBL))

    def __add_del_button_cb(self, widget, n):
        """
        This is the call-back handling the buttons to add or delete nodes
        """

        # Get the selected row in the treeview and extract the treestore, the
        # iter reference as well as child and parent iters from it
        treeselection = self.treeview.get_selection()
        (model, iter) = treeselection.get_selected()
        parent = model.iter_parent(iter)
        child = model.iter_children(iter)

        # Let's first remove the callback which automatically updates the
        # share-mon info. We're about to edit the tree so the share-mon info
        # would be inconsistent with he tree. We'll reactive the timeout once
        # the tree has been saved.
        ar.stop()

        # Use the pixbuf to decide the type of node
        # Need to decide whether we are going to add the new node as sibling
        # or as child to the selected node
        pb = model.get_value(iter, 0)
        if ( pb == STree.fldrpb ) or ( (pb == STree.projpb) and (self.add_del_btn_lbl[n] == C.ADD_USER_LBL) ):
            # It's to be treated as an inner node if it either really is an
            # inner node or if we're adding user leaves to a project node
            is_leaf = False   # Treat selected as inner ==> add new as child
        else:
            is_leaf = True  # Treat selected as leaf ==> add new as sibling

        # Preset with empty node info depending on which type of node we plan
        # to add
        if self.add_del_btn_lbl[n] == C.ADD_NODE_LBL:
            # Format: TreeStore = gtk.TreeStore(gtk.gdk.Pixbuf, str, int, str)
            node = [ STree.fldrpb, '<none>', '<none>',
                     '--', '--', '--', '--', '--', '--', '0' ]
        elif self.add_del_btn_lbl[n] == C.ADD_USER_LBL:
            node = [ STree.userpb, '<none>', '<none>',
                     '--', '--', '--', '--', '--', '--', '0' ]
        elif self.add_del_btn_lbl[n] == C.ADD_PROJ_LBL:
            node = [ STree.projpb, '<none>', '<none>', 
                     '--', '--', '--', '--', '--', '--', '1' ]
        else:
            # must be C.DEL_NODE_LBL, so remove node from TreeStore and return
            model.remove(iter)
            STree.recalc_percentages(model, parent)
            return
        if is_leaf:
            # Add as sibling node
            model.insert_before(parent, iter, node)
        else:
            # Add as child node
            model.insert_before(iter, child, node)
            # Make sure parent node is expanded so we see the new node
            self.treeview.expand_row(model.get_path(iter), True)

    def __reset_treestore(self, model, copy, msg):
        """
        Method used to restore treestore from previous state.
        Copies the treestore pointed to by copy to model and sets that in
        our treeview. Then create a message box informing user why the
        treestore has been reset.
        """
        model = copy
        self.treeview.set_model(model)
        self.treeview.expand_all()
        MsgBox.label.set_text(msg)
        MsgBox.window.show_all()

    def __drag_data_get_data(self, treeview, context, selection, target_id,
                             etime):
        """
        Gets called when a treeview row gets selected for dragging.
        We'll capture the parent node of this selection because when a node
        gets moved out of a subtree then the who subtree will be affected in
        terms of the share distribution

        Passed arguments are as per the standard signature of this callback.
        Only 'treeview' is being used currently.
        """

        # Global vars for sharing status between the drag get_data nad
        # get_received call-backs.
        global drag_src
        global drag_src_parent
        global tscopy

        # Let's first stop auto-refreshing. The treestore and the share-mon info
        # will likely get inconsistent
        ar.stop()

        # Now capture the parent node of the selection
        treeselection = treeview.get_selection()
        ts, drag_src = treeselection.get_selected()
        drag_src_parent = ts.iter_parent(drag_src)
        # And copy the current treestore model in case we need to revert to it
        tscopy = STree.fullcopy(ts)

    def __drag_data_received_data(self, treeview, context, x, y, selection,
                                info, etime):
        """
        Gets called when a treeview selection gets dragged or dropped.
        When it finally get's dropped then x & y will contain the position
        of where it got dropped.
        """

        # Global vars for sharing status between the drag get_data nad
        # get_received call-backs.
        global drag_src
        global drag_src_parent
        global tscopy

        # Get model and drop_info from x & y
        model = treeview.get_model()
        drop_info = treeview.get_dest_row_at_pos(x, y)

        if drop_info:
            # The row actually got dropped (its value is None otherwise).
            # So let's retrieve the path (we won't need position)
            path, position = drop_info
            # And the parent for that path - the subtree belonging to this
            # parent will be affected in terms of the share distribution by
            # getting a new node dropped into it.
            drag_dest = model.get_iter(path)
            drag_dest_parent = model.iter_parent(drag_dest)
            if drag_dest_parent == None:
                # can't go higher than the root node
                drag_dest_parent = drag_dest

            # Restore previous status if user executes an illegal drag&drop
            # action.
            if model.get_value(drag_dest, 0) == STree.userpb :
                # The user node must not have children. So you can't drop
                # something to it ==> restore the old status
                self.__reset_treestore(model, tscopy,
                        'User nodes must not have children.')
                return
            if model.get_value(drag_src, 0) == STree.fldrpb and model.get_value(drag_dest, 0) == STree.projpb :
                # Folders must not appear as children to projects ==> restore
                # old status
                self.__reset_treestore(model, tscopy,
                        'Inner nodes must not appear as child of project.')
                return

            # Now recalculate the level and total % in the subtrees of the
            # parents of the source and destination of the drag & drop
            STree.recalc_percentages(model, drag_src_parent)
            STree.recalc_percentages(model, drag_dest_parent)
            # And let's invalidate the share-mon info in these trees. It
            # hardly will be right anymore. It will get updated again when the
            # tree gets saved.
            STree.invalidate_share_mon_info(model, drag_src_parent)
            STree.invalidate_share_mon_info(model, drag_dest_parent)
        return

    def __edited_cb(self, cell, path, new_text, col):
        # Hanlde edits of the name or share column of a row

        # If project or user nodes are added which don't exist in the user and
        # project lists of Grid Engine then we want to ask the user whether
        # the new user/proj should get added. That happens in a pop-up window
        # which will be launched by this call-back. Whether the user clicks OK
        # or Cancel in that pop-up window will need to get handled by another
        # call-back however and we'll need to complete modifying the TreeStore
        # and the TreeView there. So we're using the following global
        # variables to transfer the required information.
        #
        # I regard this as a bit of a hack but I haven't found a good way to
        # handle this differently. I would have like to block this call-back
        # until the other call-back associated witht he popup window is
        # finished, thereby allowing no further interaction and enabling me to
        # complete the TreeStore/TreeView modifications here. But I haven't
        # found anything in PyGTK or GTK allowing me to do that. And I also
        # didn't want to use a sleep loop here.
        global edited_path
        global edited_column
        global mod_cell_content
        global actn_qconf_opt
        global actn_qconf_add_file_content

        # Let's first remove the callback which automatically updates the
        # share-mon info. We're about to edit the tree so the share-mon info
        # would be inconsistent with he tree. We'll reactive the timeout once
        # the tree has been saved.
        ar.stop()

        # The column has been passed as user data. Now we retrieve the
        # treestore model. We also have the path from the call-back.
        # So we know where the change has occurred.
        ts = self.treeview.get_model()

        if self.colnm[col] == C.SHARESCOL_LBL:
            if not new_text.isdigit() or int(new_text) <0:
                MsgBox.label.set_text('Shares need to be integers >= 0.')
                MsgBox.window.show_all()
            else:
                ts[path][col] = new_text
                STree.recalc_percentages(ts, ts.iter_parent(ts.get_iter(path)))
            return

        # If we get here then we're changing the name column
        pb = ts[path][0]    # Use the pixbuf to differentiate the node types
        # We'll preset some strings corresponding to the node type to run
        # qconf commands later with them. These qconf commands will check
        # whether user or project names which have been entered are already
        # known in Grid Engine. If not we will add them optionally.
        # That's true except for the inner nodes. Here the name is arbitrary.
        # So we'll just add it.
        if pb == STree.userpb:
            # User node
            show_option, obj_str, add_option = '-suserl', 'User ', '-Auser'
            # The qconf -suser format
            file_fmt = ['name ' + new_text, 'oticket 0', 'fshare 0', 
                        'delete_time 0', 'default_project NONE']
        elif pb == STree.projpb:
            # Project node
            show_option, obj_str, add_option = '-sprjl', 'Project ', '-Aprj'
            # The qconf -sprj format
            file_fmt = ['name ' + new_text, 'oticket 0', 'fshare 0', 
                        'acl NONE', 'xacl NONE']
        else:
            # This is an inner node ... the name is arbitrary
            ts[path][col] = new_text
            # And we can return from this callback function
            return

        # If we get this far then we know it's either a user or project
        # node and we need to check whether the user/proj should be added.
        # We present the user with the option to add it unless the leaf node
        # is named "default" which is allowed but is an implizit name and must
        # not be added to the user or project lists. We also don't need to add
        # users or project objects which already exist, of course.
        # Run a suitable qconf show list command to check for the latter first.
        so,se,err = uge.run_cmd([uge.qconf,show_option])
        if new_text == 'default' or new_text in so.split('\n') :
            # User/Proj object name exist or it's a user/proj leaf by the name of
            # default. We just change it in TreeStore
            ts[path][col] = new_text
            # And we can return from this callback function
            return
        else:
            # It's not there - so open an info box and ask whether the
            # project or user should be added.
            ActnBox.label.set_text(obj_str + new_text +
                ' does not exist - Press ' + C.OK_LBL + ' to add.')
            ActnBox.window.show_all()

        # If we get this far then the rest will need to be handled by the
        # ActnBox we have oppened up above. Pass the required information to
        # it via the global variables below. As mentioned at the start of this
        # method, I regard this as a bit of a hack.
        edited_path = path
        edited_column = col
        mod_cell_content = new_text
        actn_qconf_opt = add_option
        actn_qconf_add_file_content = file_fmt

    def __set_editable(self, cell, tvcol):
        """ All columns in colnm_editable are set to be editable """
        for collbl in self.colnm_editable:
            n = self.colnm.index(collbl)
            cell[n].set_property('editable', True)
            tvcol[n].add_attribute(cell[n], "text", n)
            cell[n].connect('edited', self.__edited_cb, n)

    def __add_btn_vbox(self, btnbox, btns, btn_lbls, cb):
        """
        Create button vboxes for the node modification buttons and the
        save/reload/quit buttons.
        'btnbox' is the container into which the buttons get added.
        'btns' and 'btn_lbls' are the button onjects and labels.
        'cb' is the callback attached to the buttons.
        """
        for n in range(0, len(btn_lbls)):
            btns[n] = gtk.Button(btn_lbls[n])
            btnbox.pack_start(btns[n], False)
            btns[n].connect('clicked', cb, n)

class MsgBoxView(object):
    """
    Class for message/action/about/help pop-up boxes.

    Message and "About" boxes just display informative text and a button
    to quite the window.
    The "Help" box displays help information and also a button to quit
    the window. The difference to a message box is that the help text is
    contained in a scrolled window. The "help" argument in the
    constructor (see below) determines the type of window.
    The action box specifically supports the case where yet unknow users
    or projects need to be added to the system when the user wants to
    add corresponding nodes to the share tree. The action box then
    provides the user with a choice of having that automatically done or
    not based on two buttons, one to OK it the other to cancel. This logic
    is implemented in the callback invoked upon clicking buttons.
    """

    def __init__(self, buttons, msgtext, title, help=False):
        """
        Constructor for the mini-GUI for the message/action/about/help box

        'buttons' is a list of button lables for the buttons to be created
        (usually OK and potentially Cancel.
        'msgtext' is the message text to be displayed.
        'title' is the text going to the tilebar of the window.
        If 'help' is True then the message window is for displaying help
        output (menue About/Help). The help text goes into a scrolled window
        then.
        """

        # A list for the button objects
        msg_btn = [None] * len(buttons)

        # Create top-level window for the message box
        self.window = gtk.Window(gtk.WINDOW_TOPLEVEL)
        self.window.set_title(title)
        self.window.connect("destroy", lambda w: gtk.main_quit())
        self.window.set_border_width(10)

        # Create the widget (hierarchy) which will hold the text. The message
        # text will get added later.
        if help:
            # If this is a "Help" box then we need a scrolled window and
            # inside and event box.
            self.window.set_size_request(C.HELP_WIDTH,C.HELP_HEIGHT)
            msg_container = gtk.ScrolledWindow()
            evb = gtk.EventBox()
            msg_container.add_with_viewport(evb)
        else:
            # Otherwise an event box is enough.
            msg_container = gtk.EventBox()
            evb = msg_container

        # Us a vbox for vertically arranging the message area and then the
        # button(s) underneath
        vbox = gtk.VBox()

        # The buttons go into a hbox
        hbox = gtk.HButtonBox()
        for n in range(0, len(buttons)):
            msg_btn[n] = gtk.Button(buttons[n])
            hbox.pack_start(msg_btn[n])
            msg_btn[n].connect('clicked', self.__msg_box_click_cb,
                               (buttons,n))

        # Arrange the message to the top and the button(s) underneath
        vbox.pack_start(msg_container, True)
        vbox.pack_end(hbox, False)

        # Add the vbox to our top level window
        self.window.add(vbox)

        # Create a label and add it to the event box
        self.label = gtk.Label(msgtext)
        evb.add(self.label)

        # Probably not necessary as we'll do a show_all later on the gtk
        # window itself
        msg_container.show()
        self.label.show()

    def __msg_box_click_cb(self, event, data):
        """
        Callback to handle what has been clicked

        The number of buttons (from 'data' passes as argument) will tell us
        whether this is an Action Box (2 buttons) or a Message Box (1).

        Global variables being set by the ShareTreeView.__edited_cb call-back.
        The edited_cb will open up an action box in case the user is
        presented with a choice to add user or project objects. In that case
        we need to "finish the job" here in this call-back depending on what
        the user has clicked.
        The global variables allow us to do that.
        (And again, I regard it a bit hacky).
        """
        global edited_path
        global edited_column
        global mod_cell_content
        global actn_qconf_opt
        global actn_qconf_add_file_content

        # The buttons string list and the number of buttons passed as user
        # data to this call-back
        btns,n = data

        # if we only have one button (=OK) then we deal with  a message
        # window and we need to do nothing but hide the window upon
        # clicking OK
        if len(btns) > 1:
            # We've more than 1, either OK or Cancel
            if btns[n] == C.OK_LBL:
                # if the OK button is clicked then the user has told us to add
                # a user or project. All info to do that is in the global
                # variables. If it is not the OK button then it's cancel and
                # we again can just fast-forward to hide the window.
                model = STreeView.treeview.get_model()
                model[edited_path][edited_column] = mod_cell_content
                tf = tempfile.NamedTemporaryFile(**options.named_temp_file_args)
                tf
                # print tf.name
                for line in actn_qconf_add_file_content:
                    tf.write(line + '\n')
                tf.flush()
                so,se,err = uge.run_cmd([uge.qconf,actn_qconf_opt,tf.name])
        # In all cases, hid the pop-up again and return
        self.window.hide()
        return

class AutoRefresh(object):
    """
    Little class controlling autoupdating of share and usage information via
    share-mon
    """
    def __init__(self, timeout):
        self.recalc_timeout = timeout
        self.recalc_timeout_id = 0

    def start(self):
        if self.recalc_timeout == 0:
            return True
        self.recalc_timeout_id = gobject.timeout_add(self.recalc_timeout,
            read_share_mon_info)

    def stop(self):
        if self.recalc_timeout == 0:
            return True
        gobject.source_remove(self.recalc_timeout_id)

def read_share_mon_info():
    """
    Runs the share-mon command with appropriate options, then builds up a
    corresponding data structure with it and finally store the data in our
    treestore model
    """

    # Run share-mon
    so,se,err = uge.run_cmd([uge.share_mon, '-c', '1', '-t', '-d', "," ])
    
    if err == 2:
        return True

    # And parse each line of the output
    r = None
    for line in so.split('\n'):
        if len(line) < 5:
           continue
        # Make a node from this line
        n = ShareNode(line)
        if r == None:
           r = n
        else:
           r.add_child(n)

    # Now store the information in the treestore model
    model = STreeView.treeview.get_model()
    r.extract_node_data(model, model.get_iter_first())
    return True

def main():
    """ The gtk main loop """
    gtk.main()

if __name__ == '__main__':
    # Command-line options are contained in this global variable
    global options

    # ./steconst.py contains definition of constants for this app. We'll refer
    # to them via C.<const-name> throughout this application
    import steconst
    C = steconst

    # Only a simple usage check right now - see whether SGE env vars are set
    if not Usage():
        sys.exit(1)

    # Initialize the GridEngine class
    uge = GridEngine(options.product)

    # Read share tree from qconf -sstree output
    qconf_stree_output = ['']
    qconf_stree_output = uge.read_share_tree()
    if qconf_stree_output == ['']:
        # Empty output means not share tree was configured thus far.
        # So set meaningful default and save it.
        print C.DEFAULT_STREE_MSG
        qconf_stree_output = C.default_stree
        so,se,err = fwrite_share_tree(qconf_stree_output)
        if err <> 0:
            # Not successful - can't continue
            sys.stderr.write(se)
            sys.exit(err)

    # Reflect share tree in gtk.TreeStore
    # row contents are: icon, name, shares, lvl %, total %, act share,
    #     long tgt share, short tgt share, comb. usg, type
    TreeStore = gtk.TreeStore(gtk.gdk.Pixbuf, str, str, str, str, str, str,
                              str, str, str)

    # Initialize STree Class and fill share tree into TreeStore
    STree = ShareTree()
    STree.fill(TreeStore, qconf_stree_output)

    # Display share tree
    STreeView = ShareTreeView()

    # And update it with the share-mon data for the first time
    read_share_mon_info()

    # Creat message box - initially hidden
    MsgBox = MsgBoxView([C.OK_LBL], 'Press ' + C.OK_LBL + ' to Quit',
                        'Message Box')
    uge.return_errors = True # Error message now can go to the MsgBox
    # Creat message box - initially hidden
    ActnBox = MsgBoxView([C.OK_LBL, C.CANCEL_LBL],
        'Press ' + C.OK_LBL + ' to proceed and ' + C.CANCEL_LBL + ' to quit',
        'Action Box')
    # Creat an "About" message box - initially hidden
    AboutBox = MsgBoxView([C.OK_LBL], C.ABOUT_MSG,
                          'About')
    # Creat a "Help" message box - initially hidden
    HelpBox = MsgBoxView([C.OK_LBL], C.HELP_MSG,
                         'Help', True)

    # Initialize and start auto-refreshing
    ar = AutoRefresh(int(options.interval)*1000)
    ar.start()

    # Enter the main loop
    main()
