create or replace package body mk_dd
as

    function query_defaults return inc_exc_t
    as
        retval inc_exc_t;
    begin
        retval                              := query_all;
        retval.exclude_query.is_system      := 1;
        retval.exclude_query.is_hidden      := 1;
        return retval;
    end query_defaults;
    
    function query_all return inc_exc_t
    as
        "q+"    query_t;
        "q-"    query_t;
        retval  inc_exc_t;
    begin
        "q+".is_pk              := 1;
        "q+".is_fk              := 1;
        "q+".is_hidden          := 1;
        "q+".is_virtual         := 1;
        "q+".is_system          := 1;
        "q+".is_part_key        := 1;
        "q+".is_nullable        := 1;
        "q+".has_default        := 1;
        "q+".nota               := 1;
        
        retval.include_query    := "q+";
        retval.exclude_query    := "q-";
        
        return retval;
    end query_all;    

/******************************************************************************/

    function parse_options(
        str in varchar2
    )return inc_exc_t
    as
        retval       inc_exc_t;
        tokens       apex_t_varchar2;
        token        varchar2( 100 );
        empty_query  query_t;
    begin
        if str is null
        then
            retval := query_defaults( );
        elsif str = '*'
        then
            retval := query_all( );
        else
            retval  := query_defaults( );
            tokens  := apex_string.split( upper( str ), ' ' );
            for i in 1..tokens.count loop
                if tokens( i )= '*' -- parse WILDCARD token
                then
                    retval := query_all( );
                elsif substr( tokens( i ), 1, 1 )not in ( '+', '-' ) -- parse ONLY THIS token
                then
                    retval.include_query    := empty_query;
                    retval.exclude_query    := empty_query;
                    token                   := '+' || tokens( i );
                else
                    token := tokens( i );
                end if;
        

                -- parse +TOKEN
                if token like '+%'
                then
                    case token
                        when '+PK' then
                            retval.include_query.is_pk := 1;
                        when '+FK' then
                            retval.include_query.is_fk := 1;
                        when '+HIDDEN' then
                            retval.include_query.is_hidden := 1;
                        when '+VIRTUAL' then
                            retval.include_query.is_virtual := 1;
                        when '+SYSTEM' then
                            retval.include_query.is_system := 1;
                        when '+NULLABLE' then
                            retval.include_query.is_nullable := 1;
                        when '+DEFAULT' then
                            retval.include_query.has_default := 1;
                        when '+PARTKEY' then
                            retval.include_query.is_part_key := 1;
                        when '+ID' then
                            retval.include_query.is_id := 1;
                        else
                            null;
                    end case;

                end if;

                -- parse -TOKEN
                if token like '-%' then
                    case token
                        when '-PK' then
                            retval.exclude_query.is_pk := 1;
                        when '-FK' then
                            retval.exclude_query.is_fk := 1;
                        when '-HIDDEN' then
                            retval.exclude_query.is_hidden := 1;
                        when '-VIRTUAL' then
                            retval.exclude_query.is_virtual := 1;
                        when '-SYSTEM' then
                            retval.exclude_query.is_system := 1;
                        when '-NULLABLE' then
                            retval.exclude_query.is_nullable := 1;
                        when '-DEFAULT' then
                            retval.exclude_query.has_default := 1;
                        when '-PARTKEY' then
                            retval.exclude_query.is_part_key := 1;
                        when '-ID' then
                            retval.exclude_query.is_id := 1;
                        else
                            null;
                    end case;
                end if;
            end loop;
        end if;

        return retval;
    end parse_options;
/******************************************************************************/

  /**
  *  1. parse query options
  *  2. loop Cursor
  *     - convert result to common RECORD TYPE
  *     - extra filter for DEFAULT (due to LONG)
  *     - pipe row
  *  3. return
  *
  * CTE explaination
  * ---
  *   - pk_column_list     - used to identify which columns are for the Primary Key
  *   - owner_filter_data  - filters based on SCHEMA.TABLE/VIEW
  *                     - does "data normalization" (YES/NO instead of Y/N)
  *   - option_filter_data - appies a filter based on the query options (except DEFAULT option)
  *   - data               - applies final columns based on ROW_NUMBER()
  *   - main query         - filters by OWNER, TABLE_NAME, ORDER_BY
  */
  function get_columns( schema_name in varchar2, table_name in varchar2, query_str in varchar2 default null )
    return columns_nt pipelined
  as
    parsed_query inc_exc_t;
    row_buffer   column_rcd;
    empty_buffer column_rcd;

  begin
    parsed_query := parse_options(query_str);
  
    for curr in (
                  with PK_COLUMN_LIST as (
                    select c.owner,c.table_name,cc.column_name
                      ,decode(count(*) over (partition by c.owner,c.constraint_name),1,'YES')
                        SINGLE_PK_COLUMN
                    from sys.all_constraints c
                     join sys.all_cons_columns cc
                       on c.owner=cc.owner and c.constraint_name=cc.constraint_name
                    where c.OWNER=get_columns.schema_name and c.TABLE_NAME=get_columns.TABLE_NAME
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
                      ,decode(a.nullable,'Y','YES','NO') as NULLABLE
                      ,a.column_id
                      ,a.data_default -- TODO: "dd_util".LONG2VARCHAR2()
                      ,case when a.data_default is not null then 'YES' else 'NO' end as HAS_DEFAULT
                      ,a.hidden_column
                      ,a.VIRTUAL_COLUMN
                      ,a.QUALIFIED_COL_NAME
                      ,m.COMMENTS
                    $IF SYS.DBMS_DB_VERSION.VERSION >= 12 $THEN
                      ,a.USER_GENERATED
                    $END
                      ,case
                        when length(a.COLUMN_NAME) <= 100
                        then
                          a.COLUMN_NAME
                        else
                          substr(a.COLUMN_NAME, 1, 100 - 4) || '$' ||
                            row_number() over (partition by a.OWNER,a.TABLE_NAME
                                               order by case
                                                         when length(a.COLUMN_NAME) > 100
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
                        ,nvl2(p.COLUMN_NAME,'YES','NO')
                           as IS_PK
                        ,coalesce(
$IF SYS.DBMS_DB_VERSION.VERSION >= 12 $THEN
                            a.IDENTITY_COLUMN -- 12c+  (correct column name?)
$ELSE
                            NULL -- pre-12c
$END
                            ,decode(a.DATA_TYPE,'NUMBER',p.SINGLE_PK_COLUMN)
                            ,'NO'
                        )
                      as SEQ_ID_COLUMN
                      ,case
                        when 'YES'=
                        coalesce(
$IF SYS.DBMS_DB_VERSION.VERSION >= 12 $THEN
                            a.IDENTITY_COLUMN -- 12c+  (correct column name?)
$ELSE
                            NULL -- pre-12c
$END
                            ,decode(a.DATA_TYPE,'NUMBER',p.SINGLE_PK_COLUMN)
                            ,'NO'
                        )
                        then 'SEQ_ID'
                        when a.data_type = 'DATE'
                          and row_number() over (partition by a.owner,a.table_name,a.data_type order by a.column_id nulls last,a.COLUMN_NAME)
                               <= 5
                        then
                          'DATE'
                        when a.data_type = 'NUMBER'
                          and row_number() over (partition by a.owner,a.table_name,a.data_type, coalesce(
$IF SYS.DBMS_DB_VERSION.VERSION >= 12 $THEN
                            a.IDENTITY_COLUMN -- 12c+  (correct column name?)
$ELSE
                            NULL -- pre-12c
$END
                            ,decode(a.DATA_TYPE,'NUMBER',p.SINGLE_PK_COLUMN)
                            ,'NO'
                        )
                          order by a.column_id,a.column_name) <= 5
                        then
                          'NUMBER'
                        when a.data_type = 'CLOB'
                          and row_number() over (partition by a.owner,a.table_name,a.data_type
                                                order by a.column_id,a.column_name) <= 1
                        then
                          'CLOB'
                        when a.data_type = 'BLOB'
                          and row_number() over (partition by a.owner,a.table_name,a.data_type
                                                order by a.column_id,a.column_name) <= 1
                        then
                          'BLOB'
                        when a.data_type = 'XMLTYPE'
                          and row_number() over (partition by a.owner,a.table_name,a.data_type
                                                order by a.column_id,a.column_name) <=  1
                        then
                          'XMLTYPE'
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
                    where a.OWNER = get_columns.schema_name
                      and a.TABLE_NAME = get_columns.TABLE_NAME
                      and a.COLUMN_ID is not null -- VCs for FBIs
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
                      ,f.IS_PK
                      ,f.COMMENTS
                    $IF SYS.DBMS_DB_VERSION.VERSION >= 12 $THEN
                      ,f.USER_GENERATED
                    $END
                    from OWNER_TABLE_FILTERED_DATA f
                    where -- LONG data types suck -- move this to IF block post HAS_DEFAULT? column
                    ( -- include
                            get_columns.parsed_query.include_query.nota = 1
                        or ( get_columns.parsed_query.include_query.is_pk = 1 and f.IS_PK = 'YES' )
                        or ( get_columns.parsed_query.include_query.is_hidden = 1 and f.hidden_column = 'YES' )
                        or ( get_columns.parsed_query.include_query.is_virtual = 1 and f.virtual_column = 'YES' )
                        or ( get_columns.parsed_query.include_query.is_system = 1 and f.user_generated <> 'YES' )
                        or ( get_columns.parsed_query.include_query.is_nullable = 1 and f.nullable = 'YES' )
                        or ( get_columns.parsed_query.include_query.is_id = 1 and f.SEQ_ID_COLUMN = 'YES' )
                        or ( get_columns.parsed_query.include_query.has_default = 1 and f.HAS_DEFAULT = 'YES' )
                        )
                      and not  ( -- include
                           ( nvl(get_columns.parsed_query.exclude_query.is_pk,0) = 1 and f.IS_PK = 'YES' )
                        or ( nvl(get_columns.parsed_query.exclude_query.is_hidden,0) = 1 and f.hidden_column = 'YES' )
                        or ( nvl(get_columns.parsed_query.exclude_query.is_virtual,0) = 1 and f.virtual_column = 'YES' )
                        or ( nvl(get_columns.parsed_query.exclude_query.is_system,0) = 1 and f.user_generated <> 'YES' )
                        or ( nvl(get_columns.parsed_query.exclude_query.is_nullable,0) = 1 and f.nullable = 'YES' )
                        or ( nvl(get_columns.parsed_query.exclude_query.is_id,0) = 1 and f.SEQ_ID_COLUMN = 'YES' )
                        or ( nvl(get_columns.parsed_query.exclude_query.has_default,0) = 1 and f.HAS_DEFAULT = 'YES' )
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
                      ,o.IS_PK
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
                  order by OWNER,TABLE_NAME,ORDER_BY )
      loop
        row_buffer := empty_buffer;
        
        row_buffer.owner := curr.owner;
        row_buffer.table_name := curr.table_name;
        row_buffer.column_name := curr.column_name;
        row_buffer.data_type := curr.data_type;
        row_buffer.data_type_mod := curr.data_type_mod;
        row_buffer.data_type_owner := curr.data_type_owner;
        row_buffer.data_length := curr.data_length;
        row_buffer.data_precision := curr.data_precision;
        row_buffer.data_scale := curr.data_scale;
        row_buffer.char_used := curr.char_used;
        row_buffer.column_id := curr.column_id;
        row_buffer.data_default := curr.data_default;
        row_buffer.is_nullable := curr.nullable;
        row_buffer.is_identity := curr.seq_id_column;
        row_buffer.is_hidden := curr.hidden_column;
        row_buffer.is_virtual := curr.virtual_column;
        row_buffer.column_comments := curr.comments;
        row_buffer.data_type_desc := curr.data_type_desc;
        row_buffer.order_by := curr.order_by;
        row_buffer.order_by_desc := curr.order_by_desc;
        row_buffer.comma_first := curr.comma_first;
        row_buffer.comma_last := curr.comma_last;
        
        -- LONG data types suck
        if row_buffer.data_default <> 'NULL'
        then
          row_buffer.has_default := 'YES';
        else
          row_buffer.has_default := 'NO';
        end if;
        
        -- place filter for DEFAULT here

        -- pipe row
        pipe row (row_buffer);
        
      end loop;

    return;
  end get_columns;

/******************************************************************************/

    function unit_test_parser( str in varchar2 )
                return query_nt  pipelined
    as
        query_logic inc_exc_t;
    begin
        query_logic := parse_options( str );
        
        pipe row( query_logic.include_query );
        pipe row( query_logic.exclude_query );
        
        return;
    end unit_test_parser;
end;
/
