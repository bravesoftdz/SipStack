unit TestIdSipUdpServer;

interface

uses
  Classes, IdSipParser, IdSipUdpServer, IdUDPClient, SysUtils, TestFrameworkEx;

type
  TestTIdSipUdpServer = class(TThreadingTestCase)
  private
    Client: TIdUDPClient;
    Parser: TIdSipParser;
    Server: TIdSipUdpServer;

    procedure CheckRequest(Sender: TObject; const Request: TIdSipRequest);
    procedure CheckResponse(Sender: TObject; const Response: TIdSipResponse);
    procedure CheckTortureTest19;
    procedure CheckTortureTest21;
    procedure CheckTortureTest22;
    procedure CheckTortureTest23;
    procedure CheckTortureTest35;
    procedure CheckTortureTest40;
//    procedure CheckTortureTest41;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestMalformedRequest;
    procedure TestMalformedResponse;
    procedure TestRequest;
    procedure TestResponse;
    procedure TestTortureTest19;
    procedure TestTortureTest21;
    procedure TestTortureTest22;
    procedure TestTortureTest23;
    procedure TestTortureTest35;
    procedure TestTortureTest40;
//    procedure TestTortureTest41;
  end;

const
  DefaultTimeout = 5000;

implementation

uses
  IdSimpleParser, SyncObjs, TestFramework, TortureTests;

function Suite: ITestSuite;
begin
  Result := TTestSuite.Create('IdSipUdpServer unit tests');
  Result.AddTest(TestTIdSipUdpServer.Suite);
end;

//*******************************************************************************
//* TestTIdSipUdpServer                                                         *
//*******************************************************************************
//* TestTIdSipUdpServer Public methods ******************************************

procedure TestTIdSipUdpServer.SetUp;
begin
  inherited SetUp;

  Self.Client := TIdUDPClient.Create(nil);
  Self.Server := TIdSipUdpServer.Create(nil);

  Self.Server.Active := true;
  Self.Client.Host := '127.0.0.1';
  Self.Client.Port := Server.DefaultPort;

  Self.Parser := TIdSipParser.Create;
end;

procedure TestTIdSipUdpServer.TearDown;
begin
  Self.Parser.Free;

  Self.Server.Active := false;

  Self.Server.Free;
  Self.Client.Free;

  inherited TearDown;
end;

//* TestTIdSipUdpServer Private methods *****************************************

procedure TestTIdSipUdpServer.CheckRequest(Sender: TObject; const Request: TIdSipRequest);
begin
  try
    CheckEquals(MethodInvite, Request.Method,             'Method');
    CheckEquals('SIP/2.0',    Request.SipVersion,         'SipVersion');
    CheckEquals(29,           Request.ContentLength,      'ContentLength');
    CheckEquals(70,           Request.MaxForwards,        'Max-Forwards');

    CheckEquals('I am a message. Hear me roar!', Request.Body, 'Body');

    Self.ThreadEvent.SetEvent;
  except
    on E: Exception do begin
      Self.ExceptionType    := ExceptClass(E.ClassType);
      Self.ExceptionMessage := E.Message;
    end;
  end;
end;

procedure TestTIdSipUdpServer.CheckResponse(Sender: TObject; const Response: TIdSipResponse);
begin
  try
    CheckEquals('SIP/2.0',                       Response.SipVersion,    'SipVersion');
    CheckEquals(486,                             Response.StatusCode,    'StatusCode');
    CheckEquals('Busy Here',                     Response.StatusText,    'StatusText');
    CheckEquals('a84b4c76e66710@gw1.leo_ix.org', Response.CallID,        'CallID');
    CheckEquals(29,                              Response.ContentLength, 'ContentLength');
    CheckEquals(70,                              Response.MaxForwards,   'MaxForwards');

  CheckEquals('Via: SIP/2.0/TCP gw1.leo_ix.org;branch=z9hG4bK776asdhds',
              Response.Headers.Items[0].AsString,
              'Headers.Items[0].AsString');
  CheckEquals('Max-Forwards: 70',
              Response.Headers.Items[1].AsString,
              'Headers.Items[1].AsString');
  CheckEquals('To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>',
              Response.Headers.Items[2].AsString,
              'Headers.Items[2].AsString');
  CheckEquals('From: Case <sip:case@fried.neurons.org>;tag=1928301774',
              Response.Headers.Items[3].AsString,
              'Headers.Items[3].AsString');
  CheckEquals('Call-ID: a84b4c76e66710@gw1.leo_ix.org',
              Response.Headers.Items[4].AsString,
              'Headers.Items[4].AsString');
  CheckEquals('CSeq: 314159 INVITE',
              Response.Headers.Items[5].AsString,
              'Headers.Items[5].AsString');
  CheckEquals('Contact: sip:wintermute@tessier-ashpool.co.lu',
              Response.Headers.Items[6].AsString,
              'Headers.Items[6].AsString');
  CheckEquals('Content-Length: 29',
              Response.Headers.Items[7].AsString,
              'Headers.Items[7].AsString');
  CheckEquals(8, Response.Headers.Count, 'OtherHeaders Count');

  CheckEquals('I am a message. Hear me roar!', Response.Body, 'Body');

    Self.ThreadEvent.SetEvent;
  except
    on E: Exception do begin
      Self.ExceptionType    := ExceptClass(E.ClassType);
      Self.ExceptionMessage := E.Message;
    end;
  end;
end;

procedure TestTIdSipUdpServer.CheckTortureTest19;
var
  Response: TIdSipResponse;
  S:        TStringStream;
begin
  S := TStringStream.Create(Self.Client.ReceiveString(DefaultTimeout));
  try
    Self.Parser.Source := S;

    Response := Self.Parser.ParseAndMakeMessage as TIdSipResponse;
    try
      CheckEquals(SipVersion,    Response.SipVersion, 'SipVersion');
      CheckEquals(SIPBadRequest, Response.StatusCode, 'StatusCode');
      CheckEquals(Format(MalformedToken, [ToHeaderFull, 'To: "Mr. J. User <sip:j.user@company.com>']),
                  Response.StatusText,
                  'StatusText');
    finally
      Response.Free;
    end;
  finally
    S.Free;
  end;
end;

procedure TestTIdSipUdpServer.CheckTortureTest21;
var
  Response: TIdSipResponse;
  S:        TStringStream;
begin
  S := TStringStream.Create(Self.Client.ReceiveString(DefaultTimeout));
  try
    Self.Parser.Source := S;

    Response := Self.Parser.ParseAndMakeMessage as TIdSipResponse;
    try
      CheckEquals(SipVersion,                Response.SipVersion, 'SipVersion');
      CheckEquals(SIPBadRequest,             Response.StatusCode, 'StatusCode');
      CheckEquals(RequestUriNoAngleBrackets, Response.StatusText, 'StatusText');
    finally
      Response.Free;
    end;
  finally
    S.Free;
  end;
end;

procedure TestTIdSipUdpServer.CheckTortureTest22;
var
  Response: TIdSipResponse;
  S:        TStringStream;
begin
  S := TStringStream.Create(Self.Client.ReceiveString(DefaultTimeout));
  try
    Self.Parser.Source := S;

    Response := Self.Parser.ParseAndMakeMessage as TIdSipResponse;
    try
      CheckEquals(SipVersion,         Response.SipVersion, 'SipVersion');
      CheckEquals(SIPBadRequest,      Response.StatusCode, 'StatusCode');
      CheckEquals(RequestUriNoSpaces, Response.StatusText, 'StatusText');
    finally
      Response.Free;
    end;
  finally
    S.Free;
  end;
end;

procedure TestTIdSipUdpServer.CheckTortureTest23;
var
  Response: TIdSipResponse;
  S:        TStringStream;
begin
  S := TStringStream.Create(Self.Client.ReceiveString(DefaultTimeout));
  try
    Self.Parser.Source := S;

    Response := Self.Parser.ParseAndMakeMessage as TIdSipResponse;
    try
      CheckEquals(SipVersion,         Response.SipVersion, 'SipVersion');
      CheckEquals(SIPBadRequest,      Response.StatusCode, 'StatusCode');
      CheckEquals(RequestUriNoSpaces, Response.StatusText, 'StatusText');
    finally
      Response.Free;
    end;
  finally
    S.Free;
  end;
end;

procedure TestTIdSipUdpServer.CheckTortureTest35;
var
  Response: TIdSipResponse;
  S:        TStringStream;
begin
  S := TStringStream.Create(Self.Client.ReceiveString(DefaultTimeout));
  try
    Self.Parser.Source := S;

    Response := Self.Parser.ParseAndMakeMessage as TIdSipResponse;
    try
      CheckEquals(SipVersion,         Response.SipVersion, 'SipVersion');
      CheckEquals(SIPBadRequest,      Response.StatusCode, 'StatusCode');
      CheckEquals(Format(MalformedToken, [ExpiresHeader, 'Expires: 0 0l@company.com']),
                  Response.StatusText,
                  'StatusText');
    finally
      Response.Free;
    end;
  finally
    S.Free;
  end;
end;

procedure TestTIdSipUdpServer.CheckTortureTest40;
var
  Response: TIdSipResponse;
  S:        TStringStream;
begin
  S := TStringStream.Create(Self.Client.ReceiveString(DefaultTimeout));
  try
    Self.Parser.Source := S;

    Response := Self.Parser.ParseAndMakeMessage as TIdSipResponse;
    try
      CheckEquals(SipVersion,    Response.SipVersion, 'SipVersion');
      CheckEquals(SIPBadRequest, Response.StatusCode, 'StatusCode');
      CheckEquals(Format(MalformedToken, [FromHeaderFull, 'From:    Bell, Alexander <sip:a.g.bell@bell-tel.com>;tag=43']),
                  Response.StatusText,
                  'StatusText');
    finally
      Response.Free;
    end;
  finally
    S.Free;
  end;
end;
{
procedure TestTIdSipUdpServer.CheckTortureTest41;
var
  Response: TIdSipResponse;
  S:        TStringStream;
begin
  S := TStringStream.Create(Self.Client.ReceiveString(DefaultTimeout));
  try
    Self.Parser.Source := S;

    Response := Self.Parser.ParseAndMakeMessage as TIdSipResponse;
    try
      CheckEquals(SipVersion,                  Response.SipVersion, 'SipVersion');
      CheckEquals(SIPSIPVersionNotSupported,   Response.StatusCode, 'StatusCode');
      CheckEquals(RSSIPSIPVersionNotSupported, Response.StatusText, 'StatusText');
    finally
      Response.Free;
    end;
  finally
    S.Free;
  end;
end;
}
//* TestTIdSipUdpServer Published methods ***************************************

procedure TestTIdSipUdpServer.TestMalformedRequest;
var
  Expected: TStrings;
  Received: TStrings;
  Msg:      TIdSipMessage;
begin
  // note the semicolon in the SIP-version
  Client.Send('INVITE sip:tentacleface@rlyeh.org.au SIP/;2.0'#13#10
            + 'To: "Cthulhu" <tentacleface@rlyeh.org.au>'#13#10
            + 'From: "Great Old Ones" <greatoldones@outerdarkness.lu>'#13#10
            + 'CSeq: 0 INVITE'#13#10
            + 'Call-ID: 0'#13#10
            + 'Max-Forwards: 5'#13#10
            + 'Via: SIP/2.0/UDP 127.0.0.1:5060'#13#10
            + #13#10);

  Expected := TStringList.Create;
  try
    Msg := Parser.MakeBadRequestResponse(Format(InvalidSipVersion, ['SIP/;2.0']));
    try
      Expected.Text := Msg.AsString;
    finally
      Msg.Free;
    end;

    Received := TStringList.Create;
    try
      Received.Text := Client.ReceiveString(DefaultTimeout);

      CheckEquals(Expected, Received, 'Malformed request');
    finally
      Received.Free;
    end;
  finally
    Expected.Free;
  end;
end;

procedure TestTIdSipUdpServer.TestMalformedResponse;
begin
  Client.Send('SIP/;2.0 200 OK'#13#10
            + #13#10);

  CheckEquals('', Client.ReceiveString(DefaultTimeout), 'Response to a malformed response');
end;

procedure TestTIdSipUdpServer.TestRequest;
begin
  Server.OnRequest := Self.CheckRequest;

  Client.Send('INVITE sip:wintermute@tessier-ashpool.co.lu SIP/2.0'#13#10
            + 'Via: SIP/2.0/TCP gw1.leo_ix.org;branch=z9hG4bK776asdhds'#13#10
            + 'Max-Forwards: 70'#13#10
            + 'To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>'#13#10
            + 'From: Case <sip:case@fried.neurons.org>;tag=1928301774'#13#10
            + 'Call-ID: a84b4c76e66710@gw1.leo_ix.org'#13#10
            + 'CSeq: 314159 INVITE'#13#10
            + 'Contact: <sip:wintermute@tessier-ashpool.co.lu>'#13#10
            + 'Content-Length: 29'#13#10
            + #13#10
            + 'I am a message. Hear me roar!');

  if (Self.ThreadEvent.WaitFor(DefaultTimeout) <> wrSignaled) then
    raise Self.ExceptionType.Create(Self.ExceptionMessage);
end;

procedure TestTIdSipUdpServer.TestResponse;
begin
  Server.OnResponse := Self.CheckResponse;

  Client.Send('SIP/2.0 486 Busy Here'#13#10
            + 'Via: SIP/2.0/TCP gw1.leo_ix.org;branch=z9hG4bK776asdhds'#13#10
            + 'Max-Forwards: 70'#13#10
            + 'To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>'#13#10
            + 'From: Case <sip:case@fried.neurons.org>;tag=1928301774'#13#10
            + 'Call-ID: a84b4c76e66710@gw1.leo_ix.org'#13#10
            + 'CSeq: 314159 INVITE'#13#10
            + 'Contact: <sip:wintermute@tessier-ashpool.co.lu>'#13#10
            + 'Content-Length: 29'#13#10
            + #13#10
            + 'I am a message. Hear me roar!');

  if (Self.ThreadEvent.WaitFor(DefaultTimeout) <> wrSignaled) then
    raise Self.ExceptionType.Create(Self.ExceptionMessage);
end;

procedure TestTIdSipUdpServer.TestTortureTest19;
begin
  Self.Client.Send(TortureTest19);

  Self.CheckTortureTest19;
end;

procedure TestTIdSipUdpServer.TestTortureTest21;
begin
  Self.Client.Send(TortureTest21);

  Self.CheckTortureTest21;
end;

procedure TestTIdSipUdpServer.TestTortureTest22;
begin
  Self.Client.Send(TortureTest22);

  Self.CheckTortureTest22;
end;

procedure TestTIdSipUdpServer.TestTortureTest23;
begin
  Self.Client.Send(TortureTest23);

  Self.CheckTortureTest23;
end;

procedure TestTIdSipUdpServer.TestTortureTest35;
begin
  Self.Client.Send(TortureTest35);

  Self.CheckTortureTest35;
end;

procedure TestTIdSipUdpServer.TestTortureTest40;
begin
  Self.Client.Send(TortureTest40);

  Self.CheckTortureTest40;
end;
{
procedure TestTIdSipUdpServer.TestTortureTest41;
begin
  Self.Client.Send(TortureTest41);

  Self.CheckTortureTest41;
end;
}
initialization
  RegisterTest('SIP server using UDP', Suite);
end.
