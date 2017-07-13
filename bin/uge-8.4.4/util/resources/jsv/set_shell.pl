#!/usr/bin/perl

use strict;
use warnings;
no warnings qw/uninitialized/;

use Env qw(SGE_ROOT);
use lib "$SGE_ROOT/util/resources/jsv";
use JSV qw( :DEFAULT jsv_send_env jsv_log_info jsv_log_warning );

jsv_on_start(sub {
   jsv_send_env();
});

jsv_on_verify(sub {
   my %params = jsv_get_param_hash();
   my $do_correct = 0;
   my $log_msg = "";

   # Get the user default shell.  The are a number of ways in which this can
   # done.  Perl allows you to retrieve environment variables using the ENV
   # hash: $ENV{SHELL}.  If jsv_send_env() has been previously called and -v
   # or -V has been used, you can use the jsv_get_env method: 
   # jsv_get_env('SHELL').  Finally, you can query UNIX LDAP and search for 
   # the value:
   #
   # ldapsearch -x -b ou=people,dc=gds,o=lilly.com -s sub "uid=" | grep -i loginshell
   #
   # 

   my $shell = jsv_get_env('SHELL');
   jsv_set_param('S', $shell);

   if (exists $params{l_hard}) {
     if (exists $params{l_hard}{'3d'}) {
       jsv_sub_add_param('l_hard', 'h_vmem', '260G');
     }
   }

   jsv_correct('Job was modified before it was accepted');
}); 

jsv_main();

