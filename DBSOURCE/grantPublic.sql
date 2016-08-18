create public synonym mail_t for mail_t
/

create public synonym mail_ct for mail_ct
/


c
create public synonym mail_part_t for mail_part_t
/

create public synonym mail_part_ct for mail_part_ct
/

create public synonym mail_header_t for mail_header_t
/

create public synonym mail_header_ct for mail_header_ct
/

create public synonym mail_client for mail_client
/

grant execute on mail_client to public
/
grant execute on mail_t to public
/
grant execute on mail_ct to public
/
grant execute on mail_part_t to public
/
grant execute on mail_part_ct to public
/
grant execute on mail_header_t to public
/
grant execute on mail_header_ct to public
/

grant execute on "MailHandlerImpl" to public
/
create public synonym "MailHandlerImpl" for "MailHandlerImpl"
/
