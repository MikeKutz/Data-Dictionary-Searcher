CREATE TABLE TEST_DD_1 (
  THIS_IS_SEQ01   INT,
  THIS_IS_N001    NUMBER,
  THIS_IS_C001    VARCHAR2(10),
  THIS_IS_D001    DATE,
  THIS_IS_CLOB001  CLOB,
  THIS_IS_BLOB001  BLOB,
  THIS_IS_XMLTYPE001  XMLTYPE,
  THIS_IS_N002    INT,
  THIS_IS_N003    INT,
  THIS_IS_N004    INT,
  THIS_IS_N005    INT,
  THIS_IS_N006    INT,
  CONSTRAINT TDD_1 PRIMARY KEY (THIS_IS_SEQ01)
);
comment on table TEST_DD_1 is 'Tests logic for identifying SEQ_ID - normal table setup';


CREATE TABLE TEST_DD_2 (
  THIS_IS_SEQ01   INT,
  THIS_IS_N001    NUMBER,
  THIS_IS_C001    VARCHAR2(10),
  THIS_IS_D001    DATE,
  THIS_IS_CLOB001  CLOB,
  THIS_IS_BLOB001  BLOB,
  THIS_IS_XMLTYPE001  XMLTYPE,
  THIS_IS_N002    INT,
  THIS_IS_N003    INT,
  THIS_IS_N004    INT,
  THIS_IS_N005    INT,
  THIS_IS_N006    INT
);
comment on table TEST_DD_2 is 'Tests logic for identifying SEQ_ID against non-existing PK';


CREATE TABLE TEST_DD_3 (
  THIS_IS_SEQ01   varchar2(10),
  THIS_IS_N001    NUMBER,
  THIS_IS_C002    VARCHAR2(10),
  THIS_IS_D001    DATE,
  THIS_IS_CLOB001  CLOB,
  THIS_IS_BLOB001  BLOB,
  THIS_IS_XMLTYPE001  XMLTYPE,
  THIS_IS_N002    INT,
  THIS_IS_N003    INT,
  THIS_IS_N004    INT,
  THIS_IS_N005    INT,
  THIS_IS_N006    INT,
  CONSTRAINT TDD_3 PRIMARY KEY (THIS_IS_SEQ01)
);

comment on table TEST_DD_3 is 'Tests logic for identifying SEQ_ID against non-number single PK';

SET SERVEROUTPUT ON;

declare
 l_schema     varchar2(30) := USER;
 l_table_name varchar2(30) := 'TEST_DD_1';

begin
dbms_output.put_line(' create VIEW ' || l_schema || '.' || l_table_name || '_view
as
SELECT');


for o in "dd"."Columns"(l_schema, l_table_name ) -- simple test
--for o in "dd"."Columns"(l_schema, l_table_name, include_options => "dd".PK_COLUMNS ) -- show only PK columns
--for o in "dd"."Columns"(l_schema, l_table_name, include_options => "dd".PK_COLUMNS, exclude_options => "dd".NO_FILTER ) -- same as 2 (unless you have hidden PK columns)
--for o in "dd"."Columns"(l_schema, l_table_name, exclude_options => "dd".DEFAULT_EXCLUDE + "dd".PK_COLUMNS ) -- shows non-PK columns
--for o in "dd"."Columns"(l_schema, l_table_name, exclude_options => "dd".NO_FILTER ) -- shows hidden BLOB column created for XMLType (12c has USER_GENERATED column)
loop

if o.data_type in ('NUMBER','DATE','VARCHAR2') then
DBMS_OUTPUT.PUT_LINE( o.comma_first || 'CAST ( '|| o.collection_column_name || ' as '
                   || o.data_type_desc || ' ) as "' || o.column_name
                   || '"   -- ' || o.comma_last || ' -- Data is stored as ' || o.collection_data_type );
else
dbms_output.put_line( o.comma_first || o.collection_column_name || ' as "' || o.column_name || '"   -- ' || o.comma_last || ' -- Data is stored as ' || o.collection_data_type );
end if;

end loop;

dbms_output.put_line( 'from APEX_COLLECTIONS
WHERE COLLECTION_NAME = ''' || UPPER( l_schema || '_' || l_table_name ) || ''';' );


end;
/

/**  cleanup script
drop table test_dd_1;
drop table test_dd_2;
drop table test_dd_3;
*/

