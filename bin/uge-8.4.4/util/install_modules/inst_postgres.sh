#! /bin/sh
#
# SGE configuration script (Installation/Uninstallation/Upgrade/Downgrade)
# Scriptname: inst_postgres.sh
# Module: postgres db install functions
#
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

HAVE_POSTGRES_SPOOLING="true"

#SetSpoolingOptionsPostgres()
# $1 - postgres spooling options (from backup?)

SetSpoolingOptionsPostgres()
{
   SPOOLING_METHOD=postgres
   SPOOLING_LIB=libspoolp
   SPOOLING_ARGS=""
   if [ "$AUTO" = "true" ]; then
      SPOOLING_ARGS="$PG_SPOOLING_ARGS"

      if [ -z "$PG_SPOOLING_ARGS" ]; then
         $INFOTEXT -log "Please enter a valid Postgres connection string as PG_SPOOLING_ARGS"
         MoveLog
         exit 1
      fi

      SpoolingPGCheckParams
   fi
   if [ "$QMASTER" = "install" ]; then

      done="false"

      while [ $done = "false" ]; do
         $CLEAR
         SpoolingPostgresQueryChange
         SpoolingPostgresCheckParams
         if [ $? -eq 0 ]; then
            done="true"
         else
             $INFOTEXT -wait -auto $AUTO -n "\nHit <RETURN> to continue >> "
         fi
      done
   fi
}


# read Postgres connection string, e.g.
# host=mypghost dbname=uge user=sgeadmin
SpoolingPostgresQueryChange()
{
   $INFOTEXT -u "\nPostgreSQL Database spooling parameters"
   $INFOTEXT -n "\nThe spooling parameters define which PostgreSQL database will be used\n" \
                "for spooling and how to connect to this database.\n\n" \
                "It is a space separated list of key=value pairs, usually it is necessary\n" \
                "to specify the host, dbname and user attributes, e.g.\n" \
                "host=mydbhost dbname=ugespooling user=ugeadmin\n\n" \
                "If your PostgreSQL Database is configured to require authentication by password\n" \
                "do not specify a password in the connection string but use the .pgpass file mechanism.\n\n" \
                "See also the PostgreSQL documentation, section libpq - C Library for more information.\n"

   if [ "$AUTO" = "true" ]; then
      SPOOLING_DIR="$PG_SPOOLING_ARGS"
   else
     $INFOTEXT -n "\nEnter the connection string for connecting to your PostgreSQL Database Server >> "
     SPOOLING_ARGS=`Enter $SPOOLING_ARGS`
   fi
}

SpoolingPostgresCheckParams()
{
   # try to connect to the PostgreSQL database
   ADMINRUN_NO_EXIT="true"
   ExecuteAsAdmin $SPOOLINIT $SPOOLING_METHOD $SPOOLING_LIB "$SPOOLING_ARGS" "connect"
   exit_status=$?
   unset ADMINRUN_NO_EXIT
   return $exit_status
}


DoBackup_postgres()
{
   echo "DoBackup_postgres dumping to $backup_dir/$DATE.dump"
   DUMPIT="$SGE_UTILBIN/pg_dump"
   PGARGS="-h $pg_host -U $pg_user"
   if [ ! -z "$pg_port" ]; then
      PGARGS="$PGARGS -p $pg_port"
   fi
   ExecuteAsAdmin $DUMPIT -t config -f $backup_dir/$DATE.dump $PGARGS $pg_dbname
}


DoRestore_postgres()
{
   dump_dir=$1
   DB_LOAD="$SGE_UTILBIN/psql"
   PGARGS="-h $pg_host -U $pg_user"
   if [ ! -z "$pg_port" ]; then
      PGARGS="$PGARGS -p $pg_port"
   fi

   # delete the config and job tables should they exist
   ADMINRUN_NO_EXIT="true"
   ExecuteAsAdmin $DB_LOAD $PGARGS -c "DROP INDEX IF EXISTS config_key" $pg_dbname
   ExecuteAsAdmin $DB_LOAD $PGARGS -c "DROP TABLE IF EXISTS config" $pg_dbname
   unset ADMINRUN_NO_EXIT

   # restore the latest dump file
   dump_file=`ls -t1 $dump_dir/*.dump | head`
   echo "restoring PostgreSQL dump file $dump_file"
   ExecuteAsAdmin $DB_LOAD -f $dump_file $PGARGS $pg_dbname
}


