create or replace package mk_dd authid current_user as
    /**
    * Data Dictionary Search Engines
    *===
    *   By MikeKutz (MK)
    *
    * Search Functions
    * ---
    *  get_columns() - simple column name search
    *  *others*      - TBD
    *
    * SEARCH OPTIONS
    * ---
    * Space separated list of tokens
    * 
    * default is `* -hidden -system`
    *
    * - prefix of `+` = Include this column type
    * - prefix of `-` = Exclude this column type
    * - no prefix = Only show this columns time. (only one)
    * - `*` = wild card (show ALL column)
    *
    * List of Tokens
    * ---
    * - `PK` - Primary Key column
    * - `ID` - Identity Column (or "only PK column that is type NUMBER")
    * - `NULLABLE` - nullable/not null columns
    * - `HIDDEN` - Hidden columne
    * - `VIRTUAL` - virtual columns
    * - `SYSTEM`  - System generated column (12c+)
    * - `DEFAULT` - column has a DEFAULT value (bugged)
    * - `PARTKEY` - Partition key (not yet available)
    * - `FK` - Column is a Foreign Key column (not yet available)
    *
    * Examples
    * ===
    * To get only PK columns, use `PK`
    * To get non PK columns/non virtual columns, use `-PK -VIRTUAL`
    * To get only Virtual Column, use `VC`
    *
    * @headcom
    */

    type query_t is record(
                             is_pk        number( 1 ) 
                            ,is_fk        number( 1 )
                            ,is_hidden    number( 1 )
                            ,is_virtual   number( 1 )
                            ,is_system    number( 1 )
                            ,is_part_key  number( 1 )
                            ,is_nullable  number( 1 )
                            ,is_id        number( 1 )
                            ,has_default  number( 1 )
                            ,nota         number( 1 ) -- none of the above
                        );
    type query_nt is table of query_t;
    type inc_exc_t is record(
             include_query  query_t
            ,exclude_query  query_t
        );
    
    type column_rcd is record(
                                owner                   varchar2( 128 byte )
                                ,table_name              varchar2( 128 byte )
                                ,column_name             varchar2( 128 byte )
                                ,data_type               varchar2( 128 byte )
                                ,data_type_mod           int
                                ,data_type_owner         varchar2( 128 byte )
                                ,data_length             int
                                ,data_precision          int
                                ,data_scale              int
                                ,char_used               varchar2( 4 )
                                ,column_id               int
                                ,data_default            varchar2( 4000 )
                                ,is_nullable             varchar2( 3 ) -- decoded to YES/NO
                                ,is_identity             varchar2( 3 )
                                ,is_hidden               varchar2( 3 )
                                ,is_virtual              varchar2( 3 )
                                ,has_default             varchar2( 3 )
                                ,column_comments         varchar2( 32767 )
                                ,data_type_desc          varchar2( 100 )
                                ,order_by                int
                                ,order_by_desc           int
                                ,comma_first             varchar2( 1 )
                                ,comma_last              varchar2( 1 )
                                ,collection_column_name  varchar2( 128 byte ) --For APEX collection
                                ,collection_data_type    varchar2( 128 byte ) --For APEX Collection
                              );
    type columns_nt is
        table of column_rcd;
        
    /**
    * returns system default query options
    */
    function query_defaults return inc_exc_t;

    /**
    * returns query option signifing "I want all columns"
    */
    function query_all return inc_exc_t;

    /**
    * parse a string into Include and Exclude query options
    *
    * @parms str    input string
    */
    function parse_options(
        str in varchar2
    )return inc_exc_t;

    /**
    * Main search function for searching Columns from the Data Dictionary
    *
    * @parms schema_name  owner of the table
    * @parms table_name   table/view name
    * @parms query_str    query string
    */
    function get_columns(
        schema_name  in  varchar2
       ,table_name   in  varchar2
       ,query_str    in  varchar2 default null
    ) return columns_nt pipelined;

    /**
    * Table Function to Unit Test the `parse_options` function
    *
    * @parms    str   String of options to parse
    */
    function unit_test_parser(
        str in varchar2
    )return query_nt
        pipelined;

end;
/
