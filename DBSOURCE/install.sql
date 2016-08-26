

/*
       Copyright 2009 Carsten Czarski


Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

/*
 * Package:      PL/SQL MAIL_CLIENT
 * Script:       Installation script
 * Author:       Carsten Czarski [carsten.czarski@gmx.de]
 * Contributors: Andre Meier
 * Version  0.2 (20090625) 
 */

set define off

create or replace java source named "MailHandler" as 
import java.sql.Connection;
import java.sql.DriverManager;

import java.util.Properties;
import java.util.Vector;

import javax.mail.Folder;
import javax.mail.FetchProfile;
import javax.mail.Message;
import javax.mail.Session;
import javax.mail.Store;
import javax.mail.Flags;
import javax.mail.BodyPart;
import javax.mail.Part;
import javax.mail.Multipart;
import javax.mail.Header;
import javax.mail.internet.InternetAddress;

import java.io.*;

import oracle.sql.ARRAY;
import oracle.sql.ArrayDescriptor;
import oracle.sql.STRUCT;
import oracle.sql.CLOB;
import oracle.sql.StructDescriptor;

import oracle.jdbc.*;
import oracle.jdbc2.*;
import oracle.sql.*;
import java.sql.*;
import java.util.*;

import java.math.BigDecimal;

public class MailHandlerImpl implements SQLData {
  static final int TEMPLOB_DURATION = BLOB.DURATION_SESSION;


  static Session oMailSession = null;
  static Store   oMailStore   = null;
  static Folder  oCurrentFolder = null;

  static boolean bIsConnected = false;

  private        int        iMessageNumber;
  private        String     sSubject;
  private        String     sSender;
  private        String     sSenderEmail;
  private        java.sql.Timestamp  dSentDate;
  private        String     sDeleted;
  private        String     sRead;
  private        String     sRecent;
  private        String     sAnswered;
  private        String     sContentType;
  private        int        iSize;

  private        String     sqlType;
  
  /*
   * If you're intending to change the top level object names
   * (MAIL_T, MAIL_CLIENT) to custom names, make sure to change
   * the names also here. This is important for proper functioning
   */

  private static String TYPENAME_MAIL_T = "MAIL_T";
  private static String TYPENAME_MAIL_CT = "MAIL_CT";
  private static String TYPENAME_MAIL_HEADER_T = "MAIL_HEADER_T";
  private static String TYPENAME_MAIL_HEADER_CT = "MAIL_HEADER_CT";
  private static String TYPENAME_MAIL_PART_T = "MAIL_PART_T";
  private static String TYPENAME_MAIL_PART_CT = "MAIL_PART_CT";

  public static String getObjectTypeOwner(Connection con) throws Exception {
    String sFileTypeOwner = null;
    CallableStatement stmt = con.prepareCall("begin dbms_utility.name_resolve(?,?,?,?,?,?,?,?); end;");
    stmt.setString(1, TYPENAME_MAIL_T);
    stmt.setInt(2, 7);
    stmt.registerOutParameter(3, java.sql.Types.VARCHAR);
    stmt.registerOutParameter(4, java.sql.Types.VARCHAR);
    stmt.registerOutParameter(5, java.sql.Types.VARCHAR);
    stmt.registerOutParameter(6, java.sql.Types.VARCHAR);
    stmt.registerOutParameter(7, oracle.jdbc.OracleTypes.NUMBER);
    stmt.registerOutParameter(8, oracle.jdbc.OracleTypes.NUMBER);
    stmt.execute();
    sFileTypeOwner = stmt.getString(3);
    stmt.close();
    return sFileTypeOwner;
  }

 
  private static Object[] convertMessageToObject(Message oMsg) throws Exception {
    Object[] mailHeader = new Object[11];
    String sPersonal = null;
    String sContentType = null;
    mailHeader[0] = new BigDecimal(oMsg.getMessageNumber());
    if (oMsg.getSubject() == null) {
      mailHeader[1] = new String("");
    } else {
      mailHeader[1] = new String(oMsg.getSubject());
    }
    sPersonal = ((InternetAddress)(oMsg.getFrom()[0])).getPersonal();
    if (sPersonal == null) {
      mailHeader[2] = new String("");
    } else {
      mailHeader[2] = new String(sPersonal);
    }
    mailHeader[3] = new String(((InternetAddress)(oMsg.getFrom()[0])).getAddress());
    mailHeader[4] = new java.sql.Timestamp(oMsg.getSentDate().getTime());
    mailHeader[5] = (oMsg.isSet(Flags.Flag.DELETED)?"Y":"N"); 
    mailHeader[6] = (oMsg.isSet(Flags.Flag.SEEN)?"Y":"N"); 
    mailHeader[7] = (oMsg.isSet(Flags.Flag.RECENT)?"Y":"N"); 
    mailHeader[8] = (oMsg.isSet(Flags.Flag.ANSWERED)?"Y":"N"); 
    sContentType = oMsg.getContentType();
    if (sContentType != null) {
      if (sContentType.indexOf(';') != -1) {
        mailHeader[9] = sContentType.substring(0, sContentType.indexOf(';'));
      } else {
        mailHeader[9] = sContentType;
      }
    } else {
      mailHeader[9] = null;
    }
    mailHeader[10] = new BigDecimal(oMsg.getSize()); 
    return mailHeader; 
  }

  private static STRUCT convertObjectToStruct(Object[] obj) 
  throws Exception {
    Connection con = DriverManager.getConnection("jdbc:default:connection:");
    StructDescriptor rDescr = StructDescriptor.createDescriptor(getObjectTypeOwner(con)+"."+TYPENAME_MAIL_T, con);
    return new STRUCT(rDescr, con, obj);
  }

  private Folder getCurrentFolder() {
    return MailHandlerImpl.oCurrentFolder;
  }


  public static void connectToServer(String sHost, int iPort, String sProtocol, String sUser, String sPass)
  throws Exception {
    if (bIsConnected) {
      throw new Exception("Already connected to a mailserver - disconnect first");
    }
    Properties props = new Properties();
    props.setProperty("mail.store.protocol", sProtocol);

    oMailSession = Session.getDefaultInstance(props);
    oMailStore   = oMailSession.getStore();
    oMailStore.connect(sHost, iPort, sUser, sPass);
    bIsConnected = true;
  }

  public static void disconnectFromServer() throws Exception {
    if (bIsConnected) {
      oMailStore.close();
      bIsConnected = false;
    } else {
    }
  }

  public static void openInbox() throws Exception {
    openFolder("INBOX");
  }

  public static void openFolder(String sFolderName) throws Exception {
    if (oCurrentFolder != null) {
      if (oCurrentFolder.isOpen()) {
        closeFolder();
      }
    }
    oCurrentFolder = oMailStore.getFolder(sFolderName);
    oCurrentFolder.open(Folder.READ_WRITE);
  }

  public static void closeFolder() throws Exception {
    oCurrentFolder.close(false);
  }

  public static void expungeFolderPop3() throws Exception {
    oCurrentFolder.close(true);
  }


  public static void expungeFolder() throws Exception {
    oCurrentFolder.expunge();
  }
   
  public CLOB getMailSimpleContentClob(boolean bSimpleContentOnly) throws Exception {
    Connection con = DriverManager.getConnection("jdbc:default:connection:");
    CLOB mailBody = null;
    
    String sMailContent = getMailSimpleContent(bSimpleContentOnly);
    if (sMailContent == null) {
      mailBody = null;
    } else {
      mailBody = CLOB.createTemporary(con, true, CLOB.DURATION_SESSION);
      Writer  oClobWriter = mailBody.setCharacterStream(0L);
      oClobWriter.write(sMailContent);
      oClobWriter.close();
    }
    return mailBody;
  }

  public CLOB getMailSimpleContentClob() throws Exception {
    return getMailSimpleContentClob(true);
  }

  public CLOB getMailContentClob() throws Exception {
    return getMailSimpleContentClob(false);
  }

  public String getContentType() throws Exception {
    Message msg = getCurrentFolder().getMessage(iMessageNumber);
    return msg.getContentType();
  }

  public int getPartCount() throws Exception {
    return getMailContentPartChildCount("");
  }

  public String getMailSimpleContent(boolean bSimpleContentOnly) throws Exception {
    String sMailContent = null;

    Message msg = getCurrentFolder().getMessage(iMessageNumber);
    Object oContent = msg.getContent();
    if (oContent instanceof java.lang.String) {
      sMailContent = (String)oContent;
    } else {
      if (!bSimpleContentOnly) {
        if (oContent instanceof javax.mail.Multipart) {
          BodyPart bp = ((Multipart)oContent).getBodyPart(0);
          if (bp.getContent() instanceof java.lang.String) {
            sMailContent = (String)bp.getContent();
          }
        }
      } 
    }
    return sMailContent;
  }

  public String getMailSimpleContent() throws Exception {
    return getMailSimpleContent(true);
  }

  public String getMailContent() throws Exception {
    return getMailSimpleContent(false);
  }



  private Part traverseToPart(Message startMsg, String sPartIndexes) throws Exception {
    StringTokenizer st       = null;
    Object          oContent = startMsg.getContent();
    Part            msg      = null;
    boolean         go       = true;
    int             iPartIdx = 0;
  
    if (sPartIndexes != null && !sPartIndexes.equals("")) {
      st = new StringTokenizer(sPartIndexes, ",");
      while (st.hasMoreTokens() && go) {
        iPartIdx = Integer.parseInt(st.nextToken());
        try {
          msg = ((Multipart)oContent).getBodyPart(iPartIdx);
        } catch (ClassCastException e) {
          throw new Exception ("Message seems not to be a multipart message");
        }
        if (msg.getContentType().toLowerCase().startsWith("multipart")) {
          go = true;
          oContent = msg.getContent();
        } else {
          go = false;
        }
      }
    } else {
      msg = startMsg;
    }
    return msg;
  }

  public ARRAY getMessageHeaders() throws Exception {
   return getMessageHeaders("");
  }

  public String getPriority() throws Exception {
    String[] sPrioHeaders = null;
    String   sPrio = null;

    Message msg = getCurrentFolder().getMessage(iMessageNumber);
    sPrioHeaders = msg.getHeader("X-Priority");
    if (sPrioHeaders != null) {
      if (sPrioHeaders.length > 0) {
        sPrio = sPrioHeaders[0];
      }
    } 
    return sPrio;
  }

  public ARRAY getMessageHeaders(String sPartIndexes) throws Exception {
    Connection con = DriverManager.getConnection("jdbc:default:connection:");
    StructDescriptor rDescr = StructDescriptor.createDescriptor(getObjectTypeOwner(con)+"." + TYPENAME_MAIL_HEADER_T, con);
    ArrayDescriptor aDescr = ArrayDescriptor.createDescriptor(getObjectTypeOwner(con)+"." + TYPENAME_MAIL_HEADER_CT, con);

    Object[] oHeader = new Object[2];
    Vector vHeaders = new Vector();
    Header oCurrentHeader = null;

    Part msg = traverseToPart(getCurrentFolder().getMessage(iMessageNumber), sPartIndexes);
    if (msg instanceof javax.mail.Part) {
      Enumeration e = msg.getAllHeaders();
      while (e.hasMoreElements()) {
        oCurrentHeader = (Header)e.nextElement();
        oHeader[0] = oCurrentHeader.getName();
        oHeader[1] = oCurrentHeader.getValue();
        vHeaders.add(new STRUCT(rDescr, con, oHeader));
      }
    }
    return new ARRAY(aDescr, con, vHeaders.toArray());
  }

  public CLOB dumpMessageClob() throws Exception {
    Connection con = DriverManager.getConnection("jdbc:default:connection:");
   
    CLOB               mailBody = null;
    InputStreamReader  isContentStream = null;
    Writer             osBlobStream = null;
    char[]             charArray = null;
    int                iCharsRead = 0;

    Message msg = getCurrentFolder().getMessage(iMessageNumber);
    isContentStream = new InputStreamReader(msg.getInputStream());

    mailBody = CLOB.createTemporary(con, true, MailHandlerImpl.TEMPLOB_DURATION);
    osBlobStream = mailBody.setCharacterStream(0L);
    charArray = new char[mailBody.getChunkSize()];
  
    while ( (iCharsRead = isContentStream.read(charArray)) != -1) {
      osBlobStream.write(charArray, 0, iCharsRead);
    }
    osBlobStream.flush();
    osBlobStream.close();
    isContentStream.close();
  
    return mailBody;
  }

  public BLOB dumpMessageBlob() throws Exception {
    Connection con = DriverManager.getConnection("jdbc:default:connection:");
   
    BLOB         mailBody = null;
    InputStream  isContentStream = null;
    OutputStream osBlobStream = null;
    byte[]       byteArray = null;
    int          iBytesRead = 0;

    Message msg = getCurrentFolder().getMessage(iMessageNumber);
    isContentStream = msg.getInputStream();

    mailBody = BLOB.createTemporary(con, true, MailHandlerImpl.TEMPLOB_DURATION);
    osBlobStream = mailBody.setBinaryStream(0L);
    byteArray = new byte[mailBody.getChunkSize()];
  
    while ( (iBytesRead = isContentStream.read(byteArray)) != -1) {
      osBlobStream.write(byteArray, 0, iBytesRead);
    }
    osBlobStream.flush();
    osBlobStream.close();
    isContentStream.close();
  
    return mailBody;
  }

  private void addMessageParts(Vector vMessageParts, Multipart msg, String sIndex) throws Exception {
    Connection con = DriverManager.getConnection("jdbc:default:connection:");
    StructDescriptor rDescr = StructDescriptor.createDescriptor(getObjectTypeOwner(con)+"." + TYPENAME_MAIL_PART_T, con);

    Object   oMsgPart[] = new Object[6];
    BodyPart bpMailPart = null;     

    for (int i=0;i<msg.getCount();i++) {
      bpMailPart = msg.getBodyPart(i);
      if (sIndex.equals("")) {
        oMsgPart[0] = String.valueOf(i);
        oMsgPart[1] = null; 
      } else {
        oMsgPart[0] = sIndex + "," + i;
        oMsgPart[1] = sIndex;
      }
      oMsgPart[2] = bpMailPart.getContentType();
      oMsgPart[3] = bpMailPart.getDisposition();
      oMsgPart[4] = new BigDecimal(bpMailPart.getSize());
      if (bpMailPart.getContentType().toLowerCase().startsWith("multipart")) {
        oMsgPart[5] = new BigDecimal( ((Multipart)bpMailPart.getContent()).getCount());
      } else {
        oMsgPart[5] = new BigDecimal(0);
      }
      vMessageParts.add(new STRUCT(rDescr, con, oMsgPart));
      if (bpMailPart.getContentType().toLowerCase().startsWith("multipart")) {
        addMessageParts(vMessageParts, ((Multipart)bpMailPart.getContent()), (String)oMsgPart[0]);
      }
    }
  }    
     
  public ARRAY getMessageInfo() throws Exception {
    Connection con = DriverManager.getConnection("jdbc:default:connection:");
    ArrayDescriptor aDescr = ArrayDescriptor.createDescriptor(getObjectTypeOwner(con)+"." + TYPENAME_MAIL_PART_CT, con);

    Vector vMessageParts = new Vector();

    Message msg = getCurrentFolder().getMessage(iMessageNumber);
  
    if (msg.getContentType().toLowerCase().startsWith("multipart")) {
      addMessageParts(vMessageParts, (Multipart)msg.getContent(), "");
    }
 
    return new ARRAY(aDescr, con, vMessageParts.toArray());
  }


  public BLOB getMailContentPartBlob(String sPartIndexes) throws Exception {
    Connection con = DriverManager.getConnection("jdbc:default:connection:");
    
    Object oContent = null;
    Part   msg = null;

    BLOB         mailBody = null;
    InputStream  isContentStream = null;
    OutputStream osBlobStream = null;
    byte[]       byteArray = null;
    int          iBytesRead = 0;

    msg = traverseToPart(getCurrentFolder().getMessage(iMessageNumber), sPartIndexes);;
    oContent = msg.getContent();

    if (!(oContent instanceof javax.mail.Multipart)) {
      mailBody = BLOB.createTemporary(con, true, MailHandlerImpl.TEMPLOB_DURATION);
      isContentStream = msg.getInputStream();
      osBlobStream = mailBody.setBinaryStream(0L);
      byteArray = new byte[mailBody.getChunkSize()];

      while ( (iBytesRead = isContentStream.read(byteArray)) != -1) {
        osBlobStream.write(byteArray, 0, iBytesRead);
      }
      osBlobStream.flush();
      osBlobStream.close();
      isContentStream.close();
    } else {
      throw new Exception("Selected Message Part is a javax.mail.Multipart object");
    }
    return mailBody;
  }

  public String getMailContentPart(String sPartIndexes) throws Exception  {
    String sPartContent = null;
    int    iPartIndex = 0;

    Object oContent = null;
    String sPartType = null;
    Part msg = null;

    msg = traverseToPart(getCurrentFolder().getMessage(iMessageNumber), sPartIndexes);;
    oContent = msg.getContent();

    if (oContent instanceof java.lang.String) {
      sPartContent = (String)oContent;
    } else {
      throw new Exception ("Selected Message Part is of type "+msg.getContentType());
    }
    return sPartContent;
  }

  public int getMailSize(String sPartIndexes) throws Exception {
    return traverseToPart(getCurrentFolder().getMessage(iMessageNumber), sPartIndexes).getSize();
  }

  public int getMailSize() throws Exception {
    return getMailSize("");
  }

  public String getMailContentPartType(String sPartIndexes) throws Exception {
    return traverseToPart(getCurrentFolder().getMessage(iMessageNumber), sPartIndexes).getContentType();
  }
  
  public int getMailContentPartChildCount(String sPartIndexes) throws Exception {
    Part msg = traverseToPart(getCurrentFolder().getMessage(iMessageNumber), sPartIndexes);
    if (msg.getContentType().toLowerCase().startsWith("multipart")) {
      return ((Multipart)msg.getContent()).getCount();
    } else {
      return 0;
    }
  }
  

  public CLOB getMailContentPartClob(String sPartIndexes) throws Exception {
    Connection con = DriverManager.getConnection("jdbc:default:connection:");
    CLOB mailBody = null;
    
    String sMailContent = getMailContentPart(sPartIndexes);
    if (sMailContent == null) {
      mailBody = null;
    } else {
      mailBody = CLOB.createTemporary(con, true, CLOB.DURATION_SESSION);
      Writer  oClobWriter = mailBody.setCharacterStream(0L);
      oClobWriter.write(sMailContent);
      oClobWriter.close();
    }
    return mailBody;
  }

  public void markRead() throws Exception {
    getCurrentFolder().getMessage(iMessageNumber).setFlag(Flags.Flag.SEEN, true);
  }

  public void markUnread() throws Exception {
    getCurrentFolder().getMessage(iMessageNumber).setFlag(Flags.Flag.SEEN, false);
  }

  public void markDeleted() throws Exception {
    getCurrentFolder().getMessage(iMessageNumber).setFlag(Flags.Flag.DELETED, true);
  }

  public void markUndeleted() throws Exception {
    getCurrentFolder().getMessage(iMessageNumber).setFlag(Flags.Flag.DELETED, false);
  }

  public static STRUCT getMessage(int iMessageNumber) throws Exception {
    Message msg = oCurrentFolder.getMessage(iMessageNumber);
    return convertObjectToStruct(convertMessageToObject(msg));
  }
   
  public static ARRAY getAllMailHeaders() 
  throws Exception {
    Connection con = DriverManager.getConnection("jdbc:default:connection:");
    ArrayDescriptor aDescr = ArrayDescriptor.createDescriptor(getObjectTypeOwner(con)+"." + TYPENAME_MAIL_CT, con);
    Vector vMails = new Vector();
      
    FetchProfile fp = new FetchProfile();
    fp.add(FetchProfile.Item.ENVELOPE);
    fp.add(FetchProfile.Item.FLAGS);

    Message message[] = oCurrentFolder.getMessages();
    oCurrentFolder.fetch(message, fp);

    for (int i=message.length-1; i>=0;i--) {
      Object[] mailHeader = convertMessageToObject(message[i]);
      vMails.add(convertObjectToStruct(mailHeader));
    }
    return new ARRAY(aDescr, con, vMails.toArray());
  }

  public void readSQL(SQLInput stream, String typeName) throws SQLException
  {
    sqlType = typeName;

    iMessageNumber = stream.readBigDecimal().intValue();
    sSubject = stream.readString();
    sSender = stream.readString();
    sSenderEmail = stream.readString();
    dSentDate = stream.readTimestamp();
    sDeleted = stream.readString();
    sRead = stream.readString();
    sRecent = stream.readString();
    sAnswered = stream.readString();
  }

  public void writeSQL(SQLOutput stream) throws SQLException
  {
    stream.writeBigDecimal(new BigDecimal(iMessageNumber));
    stream.writeString(sSubject);
    stream.writeString(sSender);
    stream.writeString(sSenderEmail);
    stream.writeTimestamp(dSentDate);
    stream.writeString(sDeleted);
    stream.writeString(sRead);
    stream.writeString(sRecent);
    stream.writeString(sAnswered);
    stream.writeString(sContentType);
    stream.writeInt(iSize);
  }

  public String getSQLTypeName() throws SQLException {
    return sqlType;
  }
}
/

alter java source "MailHandler" compile
/
sho err

create type mail_part_t as object(
  partindex           varchar2(200),
  parent_index        varchar2(200),
  content_type        varchar2(200),
  content_disposition varchar2(200),
  part_size           number,
  child_count         number
)
/

create type mail_part_ct as table of mail_part_t
/


create type mail_header_t as object(
  name    varchar2(4000),
  value   varchar2(4000)
)
/

create type mail_header_ct as table of mail_header_t
/

create or replace type mail_t authid current_user as object(
  msg_number    number,
  subject       varchar2(4000),
  sender        varchar2(200),
  sender_email  varchar2(200),
  sent_date     date,
  deleted       char(1),
  read          char(1),
  recent        char(1),
  answered      char(1),
  content_type  varchar2(200),
  message_size  number,
  member function get_simple_content_varchar2 return varchar2
    is language java name 'MailHandlerImpl.getMailSimpleContent() return java.lang.String',
  member function get_simple_content_clob return clob
    is language java name 'MailHandlerImpl.getMailSimpleContentClob() return oracle.sql.CLOB',
  member function get_content_varchar2 return varchar2
    is language java name 'MailHandlerImpl.getMailContent() return java.lang.String',
  member function get_content_clob return clob
    is language java name 'MailHandlerImpl.getMailContentClob() return oracle.sql.CLOB',
  member function get_bodypart_content_varchar2(p_partindexes in varchar2) return varchar2
    is language java name 'MailHandlerImpl.getMailContentPart(java.lang.String) return java.lang.String',
  member function get_bodypart_content_clob(p_partindexes in varchar2) return clob
    is language java name 'MailHandlerImpl.getMailContentPartClob(java.lang.String) return oracle.sql.CLOB',
  member function get_bodypart_content_blob(p_partindexes in varchar2) return blob
    is language java name 'MailHandlerImpl.getMailContentPartBlob(java.lang.String) return oracle.sql.BLOB',
  member function get_content_type return varchar2
    is language java name 'MailHandlerImpl.getContentType() return java.lang.String',
  member function get_priority return varchar2
    is language java name 'MailHandlerImpl.getPriority() return java.lang.String',
  member function get_bodypart_content_type(p_partindexes in varchar2) return varchar2
    is language java name 'MailHandlerImpl.getMailContentPartType(java.lang.String) return java.lang.String',
  member function get_multipart_count return number
    is language java name 'MailHandlerImpl.getPartCount() return int',
  member function get_bodypart_multipart_count(p_partindexes in varchar2) return number
    is language java name 'MailHandlerImpl.getMailContentPartChildCount(java.lang.String) return int',
 member function get_structure return mail_part_ct
    is language java name 'MailHandlerImpl.getMessageInfo() return oracle.sql.ARRAY',
  member procedure mark_read 
    is language java name 'MailHandlerImpl.markRead()',
  member procedure mark_unread 
    is language java name 'MailHandlerImpl.markUnread()',
  member procedure mark_deleted 
    is language java name 'MailHandlerImpl.markDeleted()',
  member procedure mark_undeleted 
    is language java name 'MailHandlerImpl.markUndeleted()',
  member function get_headers(p_partindexes in varchar2) return mail_header_ct
    is language java name 'MailHandlerImpl.getMessageHeaders(java.lang.String) return oracle.sql.ARRAY',
  member function get_headers return mail_header_ct
    is language java name 'MailHandlerImpl.getMessageHeaders() return oracle.sql.ARRAY',
  member function get_size(p_partindexes in varchar2) return number
    is language java name 'MailHandlerImpl.getMailSize(java.lang.String) return int',
  member function get_size return number
    is language java name 'MailHandlerImpl.getMailSize() return int',
  member function dump_clob return clob 
    is language java name 'MailHandlerImpl.dumpMessageClob() return oracle.sql.CLOB',
  member function dump_blob return blob 
    is language java name 'MailHandlerImpl.dumpMessageBlob() return oracle.sql.BLOB'
)
/
sho err


create or replace type mail_ct as table of mail_t
/
sho err

create or replace package mail_client authid current_user as
  PROTOCOL_IMAP constant varchar2(4) := 'imap';
  PROTOCOL_POP3 constant varchar2(4) := 'pop3';

  procedure connect_server (
    p_hostname   in varchar2,
    p_port       in number,
    p_protocol   in varchar2,
    p_userid     in varchar2,
    p_passwd     in varchar2
  );

  procedure open_inbox;
  procedure open_folder(p_folder in varchar2);
  procedure close_folder;
  procedure expunge_folder;

  procedure disconnect_server;

  function get_mail_headers return mail_ct;
  function get_message(p_message_number in number) return mail_t;
end mail_client;
/    
sho err

create or replace package body mail_client as 
  g_proto varchar2(4); 
  g_current_folder varchar2(4000);

  procedure connect_server_intern (
    p_hostname   in varchar2,
    p_port       in number,
    p_protocol   in varchar2,
    p_userid     in varchar2,
    p_passwd     in varchar2
  ) is language java name 'MailHandlerImpl.connectToServer(java.lang.String, int, java.lang.String, java.lang.String, java.lang.String)';


  procedure connect_server (
    p_hostname   in varchar2,
    p_port       in number,
    p_protocol   in varchar2,
    p_userid     in varchar2,
    p_passwd     in varchar2
  ) is 
  begin
    g_proto := p_protocol;
    connect_server_intern(p_hostname, p_port,p_protocol, p_userid, p_passwd);
  end;

  procedure disconnect_server 
    is language java name 'MailHandlerImpl.disconnectFromServer()';

  procedure open_inbox is
  begin
    open_folder('INBOX');  
  end open_inbox;

  procedure do_open_folder(p_folder in varchar2) 
    is language java name 'MailHandlerImpl.openFolder(java.lang.String)';

  procedure open_folder(p_folder in varchar2) is
  begin
    g_current_folder := p_folder;
    do_open_folder(p_folder);
  end open_folder;

  procedure close_folder
    is language java name 'MailHandlerImpl.closeFolder()';

  procedure expunge_folder_imap
    is language java name 'MailHandlerImpl.expungeFolder()';

  procedure expunge_folder_pop3
    is language java name 'MailHandlerImpl.expungeFolderPop3()';

  PROCEDURE expunge_folder
  -- thanks to Andre Meier for providing this workaround
  IS
  BEGIN
     IF g_proto = protocol_imap
     THEN
        expunge_folder_imap;
     ELSE
        -- For the Sun POP3 implementation Folder.expunge is not supported...
        -- Deshalb eigene Emulation als:
        expunge_folder_pop3;
        -- Erneuetes Öffnen der inbox nötig,
        -- weil diese durch expunge_folder_pop3 geschlossen wurde. (Siehe auch dort)
        -- Dadurch wird für den Aufrufer ein Verhalten emuliert wie beim imap-Protokoll
        open_folder(g_current_folder);
     END IF;
  END expunge_folder;

  function get_mail_headers return mail_ct 
    is language java name 'MailHandlerImpl.getAllMailHeaders() return oracle.sql.ARRAY';

  function get_message(p_message_number in number) return mail_t
    is language java name 'MailHandlerImpl.getMessage(int) return oracle.sql.STRUCT';

end mail_client;
/    
sho err


