create or replace package "dd"
authid current_user
as

  subtype "param_t"         is number(4);
  subtype "search_option_t" is int;
  subtype "boolean_t"       is varchar2(3);

  TRUE_VALUE         constant "boolean_t" := 'YES';
  FALSE_VALUE        constant "boolean_t" := 'NO';


  /*
    Maximum column size for COLUMN_NAME_20/CONSTRAINT_NAME_20/etc.
    Set this prior to generating code
  */
  PARAM_MAX_OBJECT_NAME_SIZE   "param_t" := 20;

  /* Add additional SEQ_ID row
     Set to TRUE for mapping columns to an APEX Collection
     -- TODO: move to Cursor Parameter

     default is FALSE
  */
  PARAM_INCLUDE_SEQ_ID         "param_t" := FALSE_VALUE;

  -- Maximum number of generic columns in APEX_COLLECTIONS
  PARAM_MAX_VC2       constant "param_t" := 50;
  PARAM_MAX_NUMBER    constant "param_t" := 5;
  PARAM_MAX_DATE      constant "param_t" := 5;
  PARAM_MAX_CLOB      constant "param_t" := 1;
  PARAM_MAX_BLOB      constant "param_t" := 1;
  PARAM_MAX_XMLTYPE   constant "param_t" := 1;

  -- Filtering options
  NO_FILTER                   constant "search_option_t" := null;
  ALL_COLUMNS                 constant "search_option_t" := 0;
  PK_COLUMNS                  constant "search_option_t" := power(2,0); -- not yet implemented
  HIDDEN_COLUMNS              constant "search_option_t" := power(2,1);
  SYSTEM_GENERATED_COLUMNS    constant "search_option_t" := power(2,2); -- requires >= 11.1.0.1
  VIRTUAL_COLUMNS             constant "search_option_t" := power(2,3);
  PARTITION_KEY_COLUMNS       constant "search_option_t" := power(2,4); -- not yet implemented

  -- Defaults for filtering options
  DEFAULT_INCLUDE     constant "search_option_t" := "dd".NO_FILTER;
  DEFAULT_EXCLUDE     constant "search_option_t" := "dd".HIDDEN_COLUMNS
                                                  + "dd".SYSTEM_GENERATED_COLUMNS;
  /*
    DESCRIPTION
      This cursor returns Column information from the Data Dictionary
      sorted by the (added) ORDER_BY column.

    COLUMNS RETURNED FROM THE DATA DICTIONARY
      OWNER
      table_name
      column_name
      data_type
      data_type_mod
      data_type_owner
      data_length
      data_precision
      data_scale
      CHAR_USED
      nullable -- decoded to YES/NO
      column_id
      data_default -- LONG (for now)
      hidden_column
      VIRTUAL_COLUMN
      QUALIFIED_COL_NAME
      COLUMN_COMMENTS

    ADDITIONAL COLUMNS
      DATA_TYPE_DESC  String representation of the data type (logic comes from SQL*Developer's Shift-F4)
      COLUMN_NAME_20  Similar to DOS 8.3 format for long names, this converts the COLUMN_NAME
                      to the length of "dd".PARAM_MAX_OBJECT_NAME_SIZE
      IS_PK           Is the column part of the Primary Key?  Values are 'YES' or 'NO'
      ORDER_BY        Sequential gap free number of the results ordered by COLUMN_ID
                      RESULTS ARE ORDERED BY THIS VALUE
      ORDER_BY_DESC   Sequential gap free number of the results ordered by COLUMN_ID DESC
      COMMA_FIRST     Value is a comma if the result is not the first row (ORDER_BY=1)
                      The value is a space if it is
      COMMA_LAST      Value is a comma if the result is not the last row (ORDER_BY_DESC=1)
                      The value is a space if it is

    ADDITIONAL COLUMNS FOR MAPPING TO APEX_COLLECTIONS
      SEQ_ID_COLUMN           This column is mapped to APEX_COLLECTIONS.SEQ_ID column
                              Values are 'YES' or 'NO'
      COLLECTION_COLUMN_NAME  If mappable, this is the COLUMN_NAME in APEX_COLLECTIONS -- todo
      COLLECTION_DATA_TYPE    If mappable, this is the DATA_TYPE in APEX_COLLECTIONS -- todo

    FILTERING
      Only columns that meet the conditions defined by the INCLUDE_OPTIONS parameter
      and columns that do not meet the conditions listed by the EXCLUDE_OPTIONS parameter
      are returned.

      Sum the column filter options to set the search parameters.

      By default, only non-HIDDEN and non-system generated columns are returned.


    FILTERING EXAMPLES
      To exclude Virtual Column in addition to the defaults:
        for curr in "dd"."Columns"( 'SCOTT','EMP'
                        ,EXCLUDE_OPTIONS => "dd".DEFAULT_EXCLUDE + "dd".VIRTUAL_COLUMNS )
        loop
          null;
        end loop;
      To retrieve only the PK columns:
        for curr in "dd"."Columns"( 'SCOTT','EMP', INCLUDE_OPTINS => "dd".PK_COLUMNS )
        loop
          null;
        end loop;

    COLUMN FILTER OPTIONS
      NO_FILTER                   A filter is not used
      ALL_COLUMNS                 Use for filtering all columns
      PK_COLUMNS                  Use for filtering columns that are part of the Primary Key
      HIDDEN_COLUMNS              Use for filtering Hidden Columns (HIDDEN_COLUMN='Y')
      SYSTEM_GENERATED_COLUMNS    Use for filtering system generated columns (USER_GENERATED<>'Y')
      VIRTUAL_COLUMNS             Use for filter Virtual Columns (VIRTUAL_COLUMN='Y')
      PARTITION_KEY_COLUMNS       TODO: Is this columns part of the Partitioning Key?
      DEFAULT_INCLUDE             default search condition for INCLUDE_OPTIONS
                                  value = NO_FILTER
      DEFAULT_EXCLUDE             default search condition for EXCLUDE_OPTIONS
                                  value = HIDDEN_COLUMNS + SYSTEM_GENERATED_COLUMNS

     "Column2"
       same columns as "Column"
       
       SEARCH_PARAMETER
        choices are:
          PK       - consider columns that are part of the Primary Key
          VIRTUAL  - consider columns that are VIRTUAL
          HIDDEN   - consider columns that are HIDDEN
          SYSTEM   - (12c) consider system generated columns (eg ORA$ARCHIVE_STATE)

        no prefix will force this column type (all options are AND)
        Prefix of "+" will include this column type (options are OR with results of 1)
        Prefix of "-" will exclude this column type

        HIDDEN COLUMNS ARE RETURNED BY DEFAULT
        
      EXAMPLES
        SEARCH_PARAM => 'PK'
        Returns all IS_PK columns
        
        SEARCH_PARAM => 'PK VIRTUAL'
        Returns all IS_PK columns that are also VIRTUAL columns
        
        SEARCH_PARAM => 'PK +VIRTUAL'
        Returns all IS_PK columns in addition to all VIRTUAL columns
        
        SEARCH_PARAM => 'PK -VIRTUAL'
        Returns all IS_PK columns that are not VIRTUAL columns.
        
        
        Most common searches:
        SEARCH_PARAM => '-HIDDEN'
        Returns non-hidden columns
        
        SEARCH_PARAM => 'PK'
        Returns only PK columns
        
        SEARCH_PARAM => '-HIDDEN -PK'
        Returns non-hidden, non-PK columns
        
        SEARCH_PARAM => '-HIDDEN -PK -VIRTUAL'
        Returns all visible non-pk, non-virtual columns
        

    */
  cursor "Columns"( OWNER           in SYS.ALL_TAB_COLUMNS.OWNER%type
                   ,TABLE_NAME      in SYS.ALL_TAB_COLUMNS.TABLE_NAME%type
                   ,INCLUDE_OPTIONS in "search_option_t" default DEFAULT_INCLUDE
                   ,EXCLUDE_OPTIONS in "search_option_t" default DEFAULT_EXCLUDE
                  ) is
                  with PK_COLUMN_LIST as (
                    select c.owner,c.table_name,cc.column_name
                      ,decode(count(*) over (partition by c.owner,c.constraint_name),1,"dd".TRUE_VALUE)
                        SINGLE_PK_COLUMN
                    from sys.all_constraints c
                     join sys.all_cons_columns cc
                       on c.owner=cc.owner and c.constraint_name=cc.constraint_name
                    where c.OWNER="Columns".OWNER and c.TABLE_NAME="Columns".TABLE_NAME
                      and c.constraint_type='P'
                  ), OWNER_TABLE_FILTERED_DATA as (
                    select
                       a.owner
                      ,a.table_name
                      ,a.column_name
                      ,a.data_type
                      ,a.data_type_mod
                      ,a.data_type_owner
                      ,a.data_length
                      ,a.data_precision
                      ,a.data_scale
                      ,a.CHAR_USED
                      ,decode(a.nullable,'Y',TRUE_VALUE,FALSE_VALUE) as NULLABLE
                      ,a.column_id
                      ,a.data_default -- TODO: "dd_util".LONG2VARCHAR2()
                      ,a.hidden_column
                      ,a.VIRTUAL_COLUMN
                      ,a.QUALIFIED_COL_NAME
                      ,m.COMMENTS
                      ,case
                        when length(a.COLUMN_NAME) <= "dd".PARAM_MAX_OBJECT_NAME_SIZE
                        then
                          a.COLUMN_NAME
                        else
                          substr(a.COLUMN_NAME, 1, "dd".PARAM_MAX_OBJECT_NAME_SIZE - 4) || '$' ||
                            row_number() over (partition by a.OWNER,a.TABLE_NAME
                                               order by case
                                                         when length(a.COLUMN_NAME) > "dd".PARAM_MAX_OBJECT_NAME_SIZE
                                                         then 1
                                                        end)
                       end COLUMN_NAME_20
                      ,case a.data_type 
                        when 'CHAR'     then
                          data_type||'('||a.char_length||decode(char_used,'B',' BYTE','C',' CHAR',null)||')'
                        when 'VARCHAR'  then
                          data_type||'('||a.char_length||decode(char_used,'B',' BYTE','C',' CHAR',null)||')'
                        when 'VARCHAR2' then
                          data_type||'('||a.char_length||decode(char_used,'B',' BYTE','C',' CHAR',null)||')'
                        when 'NCHAR'    then
                          data_type||'('||a.char_length||decode(char_used,'B',' BYTE','C',' CHAR',null)||')'
                        when 'NUMBER' then
                          case
                            when a.data_precision is null and a.data_scale is null
                            then
                              'NUMBER' 
                            when a.data_precision is null and a.data_scale is not null
                            then
                              'NUMBER(38,'||a.data_scale||')' 
                            else
                              a.data_type||'('||a.data_precision||','||a.data_SCALE||')'
                            end    
                        when 'NVARCHAR' then
                          a.data_type||'('||a.char_length||decode(char_used,'B',' BYTE','C',' CHAR',null)||')'
                        when 'NVARCHAR2' then
                          a.data_type||'('||a.char_length||decode(char_used,'B',' BYTE','C',' CHAR',null)||')'    
                        else
                          a.data_type
                        end DATA_TYPE_DESC
                        ,nvl2(p.COLUMN_NAME,"dd".TRUE_VALUE,"dd".FALSE_VALUE)
                           as IS_PK
                        ,coalesce(
$IF SYS.DBMS_DB_VERSION.VERSION >= 12 $THEN
                            a.IS_IDENTITY -- 12c+  (correct column name?)
$ELSE
                            NULL -- pre-12c
$END
                            ,decode(a.DATA_TYPE,'NUMBER',p.SINGLE_PK_COLUMN)
                            ,"dd".FALSE_VALUE
                        )
                      as SEQ_ID_COLUMN
                      ,case
                        when 'YES'=
                        coalesce(
$IF SYS.DBMS_DB_VERSION.VERSION >= 12 $THEN
                            a.IS_IDENTITY -- 12c+  (correct column name?)
$ELSE
                            NULL -- pre-12c
$END
                            ,decode(a.DATA_TYPE,'NUMBER',p.SINGLE_PK_COLUMN)
                            ,"dd".FALSE_VALUE
                        )
                        then 'SEQ_ID'
                        when a.data_type = 'DATE'
                          and row_number() over (partition by a.owner,a.table_name,a.data_type order by a.column_id nulls last,a.COLUMN_NAME)
                               <= "dd".PARAM_MAX_DATE
                        then
                          'DATE'
                        when a.data_type = 'NUMBER'
                          and row_number() over (partition by a.owner,a.table_name,a.data_type, coalesce(
$IF SYS.DBMS_DB_VERSION.VERSION >= 12 $THEN
                            a.IS_IDENTITY -- 12c+  (correct column name?)
$ELSE
                            NULL -- pre-12c
$END
                            ,decode(a.DATA_TYPE,'NUMBER',p.SINGLE_PK_COLUMN)
                            ,"dd".FALSE_VALUE
                        )
                          order by a.column_id,a.column_name) <= "dd".PARAM_MAX_NUMBER
                        then
                          'NUMBER'
                        when a.data_type = 'CLOB'
                          and row_number() over (partition by a.owner,a.table_name,a.data_type
                                                order by a.column_id,a.column_name) <= "dd".PARAM_MAX_CLOB
                        then
                          'CLOB'
                        when a.data_type = 'BLOB'
                          and row_number() over (partition by a.owner,a.table_name,a.data_type
                                                order by a.column_id,a.column_name) <= "dd".PARAM_MAX_BLOB
                        then
                          'BLOB'
                        when a.data_type = 'XMLTYPE'
                          and row_number() over (partition by a.owner,a.table_name,a.data_type
                                                order by a.column_id,a.column_name) <=  "dd".PARAM_MAX_BLOB
                        then
                          'XML_TYPE'
                        when a.data_type in ('VARCHAR2','NUMBER','DATE')
                        then
                          'VARCHAR2'
                      end collection_data_type
                    from SYS.ALL_TAB_COLS a
                      left outer join PK_COLUMN_LIST p
                        on a.OWNER=p.OWNER
                          and a.TABLE_NAME=p.TABLE_NAME
                          and a.COLUMN_NAME=p.COLUMN_NAME
                      left outer join SYS.ALL_COL_COMMENTS m
                        on a.OWNER=m.OWNER
                          and a.TABLE_NAME=m.TABLE_NAME
                          and a.COLUMN_NAME=m.COLUMN_NAME
                    where a.OWNER = "Columns".OWNER
                      and a.TABLE_NAME = "Columns".TABLE_NAME
                      and a.COLUMN_ID is not null -- VCs for FBIs
                  ), APEX_MAPPED_DATA as (
                    select 
                       d.owner
                      ,d.table_name
                      ,d.column_name
                      ,d.data_type
                      ,d.data_type_mod
                      ,d.data_type_owner
                      ,d.data_length
                      ,d.data_precision
                      ,d.data_scale
                      ,d.CHAR_USED
                      ,d.nullable
                      ,d.column_id
                      ,d.data_default
                      ,d.hidden_column
                      ,d.VIRTUAL_COLUMN
                      ,d.QUALIFIED_COL_NAME
                      ,d.COLUMN_NAME_20
                      ,d.DATA_TYPE_DESC
                      ,d.SEQ_ID_COLUMN
                      ,d.IS_PK
                      ,d.COMMENTS
                      ,case collection_data_type
                        when 'SEQ_ID' then 'NUMBER'
                        when 'VARCHAR2' then
                          case
                            when row_number() over (partition by owner,table_name,collection_data_type
                                                      order by column_id,column_name) <= "dd".PARAM_MAX_VC2
                            then
                              COLLECTION_DATA_TYPE
                          end
                        else
                          COLLECTION_DATA_TYPE
                      end COLLECTION_DATA_TYPE
                      ,case collection_data_type
                        when 'SEQ_ID' then 'SEQ_ID'
                        when 'VARCHAR2' then
                          case
                            when row_number() over (partition by owner,table_name,collection_data_type
                                                    order by column_id,column_name) <= "dd".PARAM_MAX_VC2
                            then
                                'C' || 
                              lpad( row_number() over (partition by owner,table_name,collection_data_type order by column_id,column_name)
                              ,3, '0')

                          end
                        when 'NUMBER' then 'N' ||
                          lpad( row_number() over (partition by owner,table_name,collection_data_type order by column_id,column_name)
                              ,3, '0')
                        when 'DATE' then 'D' ||
                          lpad( row_number() over (partition by owner,table_name,collection_data_type order by column_id,column_name)
                              ,3, '0')
                        when 'BLOB' then 'BLOB' ||
                          lpad( row_number() over (partition by owner,table_name,collection_data_type order by column_id,column_name)
                              ,3, '0')
                        when 'CLOB' then 'CLOB' ||
                          lpad( row_number() over (partition by owner,table_name,collection_data_type order by column_id,column_name)
                              ,3, '0')
                      END COLLECTION_COLUMN_NAME
                    from OWNER_TABLE_FILTERED_DATA d
                  ), OPTION_FILTERED_DATA as (
                    select 
                       f.owner
                      ,f.table_name
                      ,f.column_name
                      ,f.data_type
                      ,f.data_type_mod
                      ,f.data_type_owner
                      ,f.data_length
                      ,f.data_precision
                      ,f.data_scale
                      ,f.CHAR_USED
                      ,f.nullable
                      ,f.column_id
                      ,f.data_default
                      ,f.hidden_column
                      ,f.VIRTUAL_COLUMN
                      ,f.QUALIFIED_COL_NAME
                      ,f.COLUMN_NAME_20
                      ,f.DATA_TYPE_DESC
                      ,f.SEQ_ID_COLUMN
                      ,f.collection_data_type
                      ,f.IS_PK
                      ,f.COLLECTION_COLUMN_NAME
                      ,f.COMMENTS
                    from APEX_MAPPED_DATA f
                    where
                      ( -- filter INCLUDE_OPTIONS
                        "Columns".INCLUDE_OPTIONS is null
                        or "Columns".INCLUDE_OPTIONS = "dd".ALL_COLUMNS
                        or (bitand( "Columns".INCLUDE_OPTIONS,"dd".PK_COLUMNS) > 0
                            and f.IS_PK = "dd".TRUE_VALUE)
                        or (bitand( "Columns".INCLUDE_OPTIONS,"dd".HIDDEN_COLUMNS) > 0
                            and f.HIDDEN_COLUMN='YES')
                        or (bitand( "Columns".INCLUDE_OPTIONS,"dd".SYSTEM_GENERATED_COLUMNS) > 0
                            and
                            $IF SYS.DBMS_DB_VERSION.VERSION >= 11 $THEN
                              f.USER_GENERATED <> 'YES' 
                            $ELSE
                              1=0
                            $END
                          )

                        or (bitand( "Columns".INCLUDE_OPTIONS,"dd".VIRTUAL_COLUMNS) > 0
                            and f.VIRTUAL_COLUMN='YES')
                      ) and
                      ( -- filter EXCLUDE_OPTIONS
                        "Columns".EXCLUDE_OPTIONS is not null
                        or not (
                          "Columns".EXCLUDE_OPTIONS = "dd".ALL_COLUMNS
                          or (bitand( "Columns".EXCLUDE_OPTIONS,"dd".PK_COLUMNS) > 0
                              and 1=0)
                          or (bitand( "Columns".EXCLUDE_OPTIONS,"dd".HIDDEN_COLUMNS) > 0
                              and f.HIDDEN_COLUMN='YES')
                          or (bitand( "Columns".EXCLUDE_OPTIONS,"dd".SYSTEM_GENERATED_COLUMNS) > 0
                              and
                              $IF SYS.DBMS_DB_VERSION.VERSION >= 11 $THEN
                                f.USER_GENERATED <> 'YES' 
                              $ELSE
                                1=0
                              $END
                            )
                          or (bitand( "Columns".EXCLUDE_OPTIONS,"dd".VIRTUAL_COLUMNS) > 0
                              and f.VIRTUAL_COLUMN='YES')
                        )
                      )

                  ), data as (
                    select
                       o.owner
                      ,o.table_name
                      ,o.column_name
                      ,o.data_type
                      ,o.data_type_mod
                      ,o.data_type_owner
                      ,o.data_length
                      ,o.data_precision
                      ,o.data_scale
                      ,o.CHAR_USED
                      ,o.nullable
                      ,o.column_id
                      ,o.data_default
                      ,o.hidden_column
                      ,o.VIRTUAL_COLUMN
                      ,o.QUALIFIED_COL_NAME
                      ,o.COLUMN_NAME_20
                      ,o.DATA_TYPE_DESC
                      ,o.SEQ_ID_COLUMN
                      ,o.collection_data_type
                      ,o.IS_PK
                      ,o.COLLECTION_COLUMN_NAME
                      ,o.COMMENTS
                        ,row_number() over (partition by o.OWNER,o.TABLE_NAME order by o.COLUMN_ID)
                          as ORDER_BY
                        ,decode( row_number() over (partition by o.OWNER,o.TABLE_NAME order by o.COLUMN_ID)
                                ,1, ' ', ',' ) as COMMA_FIRST
                        ,row_number() over (partition by o.OWNER,o.TABLE_NAME order by o.COLUMN_ID desc)
                          as ORDER_BY_DESC
                        ,decode( row_number() over (partition by o.OWNER,o.TABLE_NAME order by o.COLUMN_ID desc)
                                ,1, ' ', ',' ) as COMMA_LAST
                      from OPTION_FILTERED_DATA o
                  )
                  select *
                  from data d
                  order by OWNER,TABLE_NAME,ORDER_BY;

  cursor "Columns2"( OWNER           in SYS.ALL_TAB_COLUMNS.OWNER%type
                   ,TABLE_NAME       in SYS.ALL_TAB_COLUMNS.TABLE_NAME%type
                   ,SEARCH_OPTION    in VARCHAR2
                  ) is
                  with PK_COLUMN_LIST as (
                    select c.owner,c.table_name,cc.column_name
                      ,decode(count(*) over (partition by c.owner,c.constraint_name),1,"dd".TRUE_VALUE)
                        SINGLE_PK_COLUMN
                    from sys.all_constraints c
                     join sys.all_cons_columns cc
                       on c.owner=cc.owner and c.constraint_name=cc.constraint_name
                    where c.OWNER="Columns2".OWNER and c.TABLE_NAME="Columns2".TABLE_NAME
                      and c.constraint_type='P'
                  ), OWNER_TABLE_FILTERED_DATA as (
                    select
                       a.owner
                      ,a.table_name
                      ,a.column_name
                      ,a.data_type
                      ,a.data_type_mod
                      ,a.data_type_owner
                      ,a.data_length
                      ,a.data_precision
                      ,a.data_scale
                      ,a.CHAR_USED
                      ,decode(a.nullable,'Y',TRUE_VALUE,FALSE_VALUE) as NULLABLE
                      ,a.column_id
                      ,a.data_default -- TODO: "dd_util".LONG2VARCHAR2()
                      ,a.hidden_column
                      ,a.VIRTUAL_COLUMN
                      ,a.QUALIFIED_COL_NAME
                      ,m.COMMENTS
                      ,case
                        when length(a.COLUMN_NAME) <= "dd".PARAM_MAX_OBJECT_NAME_SIZE
                        then
                          a.COLUMN_NAME
                        else
                          substr(a.COLUMN_NAME, 1, "dd".PARAM_MAX_OBJECT_NAME_SIZE - 4) || '$' ||
                            row_number() over (partition by a.OWNER,a.TABLE_NAME
                                               order by case
                                                         when length(a.COLUMN_NAME) > "dd".PARAM_MAX_OBJECT_NAME_SIZE
                                                         then 1
                                                        end)
                       end COLUMN_NAME_20
                      ,case a.data_type 
                        when 'CHAR'     then
                          data_type||'('||a.char_length||decode(char_used,'B',' BYTE','C',' CHAR',null)||')'
                        when 'VARCHAR'  then
                          data_type||'('||a.char_length||decode(char_used,'B',' BYTE','C',' CHAR',null)||')'
                        when 'VARCHAR2' then
                          data_type||'('||a.char_length||decode(char_used,'B',' BYTE','C',' CHAR',null)||')'
                        when 'NCHAR'    then
                          data_type||'('||a.char_length||decode(char_used,'B',' BYTE','C',' CHAR',null)||')'
                        when 'NUMBER' then
                          case
                            when a.data_precision is null and a.data_scale is null
                            then
                              'NUMBER' 
                            when a.data_precision is null and a.data_scale is not null
                            then
                              'NUMBER(38,'||a.data_scale||')' 
                            else
                              a.data_type||'('||a.data_precision||','||a.data_SCALE||')'
                            end    
                        when 'NVARCHAR' then
                          a.data_type||'('||a.char_length||decode(char_used,'B',' BYTE','C',' CHAR',null)||')'
                        when 'NVARCHAR2' then
                          a.data_type||'('||a.char_length||decode(char_used,'B',' BYTE','C',' CHAR',null)||')'    
                        else
                          a.data_type
                        end DATA_TYPE_DESC
                        ,nvl2(p.COLUMN_NAME,"dd".TRUE_VALUE,"dd".FALSE_VALUE)
                           as IS_PK
                        ,coalesce(
$IF SYS.DBMS_DB_VERSION.VERSION >= 12 $THEN
                            a.IS_IDENTITY -- 12c+  (correct column name?)
$ELSE
                            NULL -- pre-12c
$END
                            ,decode(a.DATA_TYPE,'NUMBER',p.SINGLE_PK_COLUMN)
                            ,"dd".FALSE_VALUE
                        )
                      as SEQ_ID_COLUMN
                      ,case
                        when 'YES'=
                        coalesce(
$IF SYS.DBMS_DB_VERSION.VERSION >= 12 $THEN
                            a.IS_IDENTITY -- 12c+  (correct column name?)
$ELSE
                            NULL -- pre-12c
$END
                            ,decode(a.DATA_TYPE,'NUMBER',p.SINGLE_PK_COLUMN)
                            ,"dd".FALSE_VALUE
                        )
                        then 'SEQ_ID'
                        when a.data_type = 'DATE'
                          and row_number() over (partition by a.owner,a.table_name,a.data_type order by a.column_id nulls last,a.COLUMN_NAME)
                               <= "dd".PARAM_MAX_DATE
                        then
                          'DATE'
                        when a.data_type = 'NUMBER'
                          and row_number() over (partition by a.owner,a.table_name,a.data_type, coalesce(
$IF SYS.DBMS_DB_VERSION.VERSION >= 12 $THEN
                            a.IS_IDENTITY -- 12c+  (correct column name?)
$ELSE
                            NULL -- pre-12c
$END
                            ,decode(a.DATA_TYPE,'NUMBER',p.SINGLE_PK_COLUMN)
                            ,"dd".FALSE_VALUE
                        )
                          order by a.column_id,a.column_name) <= "dd".PARAM_MAX_NUMBER
                        then
                          'NUMBER'
                        when a.data_type = 'CLOB'
                          and row_number() over (partition by a.owner,a.table_name,a.data_type
                                                order by a.column_id,a.column_name) <= "dd".PARAM_MAX_CLOB
                        then
                          'CLOB'
                        when a.data_type = 'BLOB'
                          and row_number() over (partition by a.owner,a.table_name,a.data_type
                                                order by a.column_id,a.column_name) <= "dd".PARAM_MAX_BLOB
                        then
                          'BLOB'
                        when a.data_type = 'XMLTYPE'
                          and row_number() over (partition by a.owner,a.table_name,a.data_type
                                                order by a.column_id,a.column_name) <=  "dd".PARAM_MAX_BLOB
                        then
                          'XML_TYPE'
                        when a.data_type in ('VARCHAR2','NUMBER','DATE')
                        then
                          'VARCHAR2'
                      end collection_data_type
                    from SYS.ALL_TAB_COLS a
                      left outer join PK_COLUMN_LIST p
                        on a.OWNER=p.OWNER
                          and a.TABLE_NAME=p.TABLE_NAME
                          and a.COLUMN_NAME=p.COLUMN_NAME
                      left outer join SYS.ALL_COL_COMMENTS m
                        on a.OWNER=m.OWNER
                          and a.TABLE_NAME=m.TABLE_NAME
                          and a.COLUMN_NAME=m.COLUMN_NAME
                    where a.OWNER = "Columns2".OWNER
                      and a.TABLE_NAME = "Columns2".TABLE_NAME
                      and a.COLUMN_ID is not null -- VCs for FBIs
                  ), APEX_MAPPED_DATA as (
                    select 
                       d.owner
                      ,d.table_name
                      ,d.column_name
                      ,d.data_type
                      ,d.data_type_mod
                      ,d.data_type_owner
                      ,d.data_length
                      ,d.data_precision
                      ,d.data_scale
                      ,d.CHAR_USED
                      ,d.nullable
                      ,d.column_id
                      ,d.data_default
                      ,d.hidden_column
                      ,d.VIRTUAL_COLUMN
                      ,d.QUALIFIED_COL_NAME
                      ,d.COLUMN_NAME_20
                      ,d.DATA_TYPE_DESC
                      ,d.SEQ_ID_COLUMN
                      ,d.IS_PK
                      ,d.COMMENTS
                      ,case collection_data_type
                        when 'SEQ_ID' then 'NUMBER'
                        when 'VARCHAR2' then
                          case
                            when row_number() over (partition by owner,table_name,collection_data_type
                                                      order by column_id,column_name) <= "dd".PARAM_MAX_VC2
                            then
                              COLLECTION_DATA_TYPE
                          end
                        else
                          COLLECTION_DATA_TYPE
                      end COLLECTION_DATA_TYPE
                      ,case collection_data_type
                        when 'SEQ_ID' then 'SEQ_ID'
                        when 'VARCHAR2' then
                          case
                            when row_number() over (partition by owner,table_name,collection_data_type
                                                    order by column_id,column_name) <= "dd".PARAM_MAX_VC2
                            then
                                'C' || 
                              lpad( row_number() over (partition by owner,table_name,collection_data_type order by column_id,column_name)
                              ,3, '0')

                          end
                        when 'NUMBER' then 'N' ||
                          lpad( row_number() over (partition by owner,table_name,collection_data_type order by column_id,column_name)
                              ,3, '0')
                        when 'DATE' then 'D' ||
                          lpad( row_number() over (partition by owner,table_name,collection_data_type order by column_id,column_name)
                              ,3, '0')
                        when 'BLOB' then 'BLOB' ||
                          lpad( row_number() over (partition by owner,table_name,collection_data_type order by column_id,column_name)
                              ,3, '0')
                        when 'CLOB' then 'CLOB' ||
                          lpad( row_number() over (partition by owner,table_name,collection_data_type order by column_id,column_name)
                              ,3, '0')
                      END COLLECTION_COLUMN_NAME
                    from OWNER_TABLE_FILTERED_DATA d
                  ), OPTION_FILTERED_DATA as (
                    select 
                       f.owner
                      ,f.table_name
                      ,f.column_name
                      ,f.data_type
                      ,f.data_type_mod
                      ,f.data_type_owner
                      ,f.data_length
                      ,f.data_precision
                      ,f.data_scale
                      ,f.CHAR_USED
                      ,f.nullable
                      ,f.column_id
                      ,f.data_default
                      ,f.hidden_column
                      ,f.VIRTUAL_COLUMN
                      ,f.QUALIFIED_COL_NAME
                      ,f.COLUMN_NAME_20
                      ,f.DATA_TYPE_DESC
                      ,f.SEQ_ID_COLUMN
                      ,f.collection_data_type
                      ,f.IS_PK
                      ,f.COLLECTION_COLUMN_NAME
                      ,f.COMMENTS
                    from APEX_MAPPED_DATA f
                    WHERE (
                      ( 1=1
                      AND IS_PK     IN ( 'YES', case when REGEXP_LIKE( SEARCH_OPTION, '(^|[^+-])PK') then '---' else 'NO' end  )
                      AND virtual_column IN ( 'YES', case when REGEXP_LIKE( SEARCH_OPTION, '(^|[^+-])VIRTUAL') then '---' else 'NO' end  )
                      and hidden_column  IN ( 'YES', case when REGEXP_LIKE( SEARCH_OPTION, '(^|[^+-])HIDDEN') then '---' else 'NO' end  )
                      ) 
                      OR 1=decode( IS_PK,'YES', case when SEARCH_OPTION like '%+PK%' then 1 ELSE 0 end ,0 )
                      OR 1=decode( virtual_column,'YES', case when SEARCH_OPTION like '%+VIRTUAL%' then 1 ELSE 0 end ,0 )
                      OR 1=decode( hidden_column,'YES', case when SEARCH_OPTION like '%+HIDDEN%' then 1 ELSE 0 end ,0 )
                      )
                      AND NOT ( 1=0
                        OR 1=decode( IS_PK,'YES', case when SEARCH_OPTION like '%-PK%' then 1 ELSE 0 end ,0 )
                        OR 1=decode( virtual_column,'YES', case when SEARCH_OPTION like '%-VIRTUAL%' then 1 ELSE 0 end ,0 )
                        OR 1=decode( hidden_column,'YES', case when SEARCH_OPTION like '%-HIDDEN%' then 1 ELSE 0 end ,0 )
                      )
                  ), data as (
                    select
                       o.owner
                      ,o.table_name
                      ,o.column_name
                      ,o.data_type
                      ,o.data_type_mod
                      ,o.data_type_owner
                      ,o.data_length
                      ,o.data_precision
                      ,o.data_scale
                      ,o.CHAR_USED
                      ,o.nullable
                      ,o.column_id
                      ,o.data_default
                      ,o.hidden_column
                      ,o.VIRTUAL_COLUMN
                      ,o.QUALIFIED_COL_NAME
                      ,o.COLUMN_NAME_20
                      ,o.DATA_TYPE_DESC
                      ,o.SEQ_ID_COLUMN
                      ,o.collection_data_type
                      ,o.IS_PK
                      ,o.COLLECTION_COLUMN_NAME
                      ,o.COMMENTS
                        ,row_number() over (partition by o.OWNER,o.TABLE_NAME order by o.COLUMN_ID)
                          as ORDER_BY
                        ,decode( row_number() over (partition by o.OWNER,o.TABLE_NAME order by o.COLUMN_ID)
                                ,1, ' ', ',' ) as COMMA_FIRST
                        ,row_number() over (partition by o.OWNER,o.TABLE_NAME order by o.COLUMN_ID desc)
                          as ORDER_BY_DESC
                        ,decode( row_number() over (partition by o.OWNER,o.TABLE_NAME order by o.COLUMN_ID desc)
                                ,1, ' ', ',' ) as COMMA_LAST
                      from OPTION_FILTERED_DATA o
                  )
                  select *
                  from data d
                  order by OWNER,TABLE_NAME,ORDER_BY;

  type "pipe_columns_t" is table of "Columns"%rowtype;

end;
/
