{
  (c) 2004 Directorate of New Technologies, Royal National Institute for Deaf people (RNID)

  The RNID licence covers this unit. Read the licence at:
      http://www.ictrnid.org.uk/docs/gw/rnid_license.txt

  This unit contains code written by:
    * Frank Shearar
}
unit IdSipTcpServer;

interface

uses
  Classes, Contnrs, IdNotification, IdSipConsts, IdSipLocator, IdSipMessage,
  IdSipServerNotifier, IdSipTcpClient, IdTCPConnection, IdTCPServer,
  IdTimerQueue, SyncObjs, SysUtils;

type
  TIdSipAddConnectionEvent = procedure(Connection: TIdTCPConnection;
                                       Request: TIdSipRequest) of object;
  TIdSipRemoveConnectionEvent = procedure(Connection: TIdTCPConnection) of object;

  // ReadTimeout = -1 implies that we never timeout the body wait. We do not
  // recommend this. ReadTimeout = n implies we wait n milliseconds for
  // the body to be received. If we haven't read Content-Length bytes by the
  // time the timeout occurs, we sever the connection.
  TIdSipTcpServer = class(TIdTCPServer)
  private
    fConnectionTimeout:  Integer;
    fOnAddConnection:    TIdSipAddConnectionEvent;
    fOnRemoveConnection: TIdSipRemoveConnectionEvent;
    fReadTimeout:        Integer;
    fTimer:              TIdTimerQueue;
    Notifier:            TIdSipServerNotifier;

    procedure AddConnection(Connection: TIdTCPConnection;
                            Request: TIdSipRequest);
    procedure DoOnException(Sender: TObject); overload;
    procedure DoOnException(Thread: TIdPeerThread;
                            Exception: Exception); overload;
    procedure DoOnReceiveMessage(Sender: TObject);
    procedure ReadBodyInto(Connection: TIdTCPConnection;
                           Message: TIdSipMessage;
                           Dest: TStringStream);
    procedure ReadMessage(Connection: TIdTCPConnection;
                          Dest: TStringStream);
    procedure ReturnInternalServerError(Connection: TIdTCPConnection;
                                        const Reason: String);
    procedure ScheduleExceptionNotification(ExceptionType: ExceptClass;
                                            const Reason: String);
    procedure ScheduleReceivedMessage(Msg: TIdSipMessage;
                                      ReceivedFrom: TIdSipConnectionBindings);
    procedure WriteMessage(Connection: TIdTCPConnection;
                           AMessage: TIdSipMessage);
  protected
    procedure DoDisconnect(AThread: TIdPeerThread); override;
    procedure DoOnExecute(AThread: TIdPeerThread);
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;

    procedure AddMessageListener(const Listener: IIdSipMessageListener);
    function  CreateClient: TIdSipTcpClient; virtual;
    function  DefaultTimeout: Cardinal; virtual;
    procedure DestroyClient(Client: TIdSipTcpClient); virtual;
    procedure RemoveMessageListener(const Listener: IIdSipMessageListener);
  published
    property ConnectionTimeout:  Integer                     read fConnectionTimeout write fConnectionTimeout;
    property OnAddConnection:    TIdSipAddConnectionEvent    read fOnAddConnection write fOnAddConnection;
    property OnRemoveConnection: TIdSipRemoveConnectionEvent read fOnRemoveConnection write fOnRemoveConnection;
    property ReadTimeout:        Integer                     read fReadTimeout write fReadTimeout;
    property Timer:              TIdTimerQueue               read fTimer write fTimer;
  end;

  // I represent a (possibly) deferred receipt of a message.
  TIdSipReceiveTCPMessageWait = class(TIdSipMessageNotifyEventWait)
  private
    fReceivedFrom: TIdSipConnectionBindings;
  public
    property ReceivedFrom: TIdSipConnectionBindings read fReceivedFrom write fReceivedFrom;
  end;

  TIdSipTcpServerClass = class of TIdSipTcpServer;

implementation

uses
  IdException, IdSipTransport;

//******************************************************************************
//* TIdSipTcpServer                                                            *
//******************************************************************************
//* TIdSipTcpServer Public methods *********************************************

constructor TIdSipTcpServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  Self.ConnectionTimeout := Self.DefaultTimeout;
  Self.DefaultPort       := TIdSipTransportRegistry.DefaultPortFor(TcpTransport);
  Self.Notifier          := TIdSipServerNotifier.Create;
  Self.ReadTimeout       := Self.DefaultTimeout;
  Self.OnExecute         := Self.DoOnExecute;
  Self.OnException       := Self.DoOnException;
end;

destructor TIdSipTcpServer.Destroy;
begin
  Self.Notifier.Free;

  inherited Destroy;
end;

procedure TIdSipTcpServer.AddMessageListener(const Listener: IIdSipMessageListener);
begin
  Self.Notifier.AddMessageListener(Listener);
end;

function TIdSipTcpServer.CreateClient: TIdSipTcpClient;
begin
  Result := TIdSipTcpClient.Create(nil);
end;

function TIdSipTcpServer.DefaultTimeout: Cardinal;
begin
  Result := 5000;
end;

procedure TIdSipTcpServer.DestroyClient(Client: TIdSipTcpClient);
begin
  Client.Free;
end;

procedure TIdSipTcpServer.RemoveMessageListener(const Listener: IIdSipMessageListener);
begin
  Self.Notifier.RemoveMessageListener(Listener);
end;

//* TIdSipTcpServer Protected methods ******************************************

procedure TIdSipTcpServer.DoDisconnect(AThread: TIdPeerThread);
begin
  if Assigned(Self.fOnRemoveConnection) then
    Self.fOnRemoveConnection(AThread.Connection);

  inherited DoDisconnect(AThread);
end;

procedure TIdSipTcpServer.DoOnExecute(AThread: TIdPeerThread);
var
  Msg:          TIdSipMessage;
  ReceivedFrom: TIdSipConnectionBindings;
  S:            TStringStream;
  ConnTimedOut: Boolean;
begin
  ConnTimedOut := false;

  ReceivedFrom.PeerIP   := AThread.Connection.Socket.Binding.PeerIP;
  ReceivedFrom.PeerPort := AThread.Connection.Socket.Binding.PeerPort;

  while AThread.Connection.Connected do begin
    AThread.Connection.ReadTimeout := Self.ReadTimeout;

    S := TStringStream.Create('');
    try
      Self.ReadMessage(AThread.Connection, S);
      Msg := TIdSipMessage.ReadMessageFrom(S);
      try
        try
          try
            Self.ReadBodyInto(AThread.Connection, Msg, S);
            Msg.ReadBody(S);
          except
            on EIdReadTimeout do
              ConnTimedOut := true;
            on EIdConnClosedGracefully do
              ConnTimedOut := true;
          end;

          // If Self.ReadBody closes the connection, we don't want to AddConnection!
          if Msg.IsRequest and not ConnTimedOut then
            Self.AddConnection(AThread.Connection, Msg as TIdSipRequest);

          Self.ScheduleReceivedMessage(Msg, ReceivedFrom);
        except
          on E: Exception do begin
            // This results in returning a 500 Internal Server Error to a response!
            Self.ReturnInternalServerError(AThread.Connection, E.Message);
            AThread.Connection.DisconnectSocket;

            Self.ScheduleExceptionNotification(ExceptClass(E.ClassType),
                                               E.Message);
          end;
        end;
      finally
        Msg.Free;
      end;
    finally
      S.Free;
    end;
  end;
end;

//* TIdSipTcpServer Private methods ********************************************

procedure TIdSipTcpServer.AddConnection(Connection: TIdTCPConnection;
                                        Request: TIdSipRequest);
begin
  if Assigned(Self.fOnAddConnection) then
    Self.fOnAddConnection(Connection, Request);
end;

procedure TIdSipTcpServer.DoOnException(Sender: TObject);
var
  FakeException: Exception;
  Wait:          TIdSipExceptionWait;
begin
  Wait := Sender as TIdSipExceptionWait;

  FakeException := Wait.ExceptionType.Create(Wait.ExceptionMsg);
  try
    Self.Notifier.NotifyListenersOfException(FakeException,
                                             Wait.Reason);
  finally
    FakeException.Free;
  end;
end;

procedure TIdSipTcpServer.DoOnException(Thread: TIdPeerThread;
                                        Exception: Exception);
begin
  Self.ScheduleExceptionNotification(ExceptClass(Exception.ClassType),
                                     Exception.Message);
end;

procedure TIdSipTcpServer.DoOnReceiveMessage(Sender: TObject);
var
  Wait: TIdSipReceiveTCPMessageWait;
begin
  Wait := Sender as TIdSipReceiveTCPMessageWait;

  if Wait.Message.IsRequest then
    Self.Notifier.NotifyListenersOfRequest(Wait.Message as TIdSipRequest,
                                           Wait.ReceivedFrom)
  else
    Self.Notifier.NotifyListenersOfResponse(Wait.Message as TIdSipResponse,
                                            Wait.ReceivedFrom);
end;

procedure TIdSipTcpServer.ReadBodyInto(Connection: TIdTCPConnection;
                                       Message: TIdSipMessage;
                                       Dest: TStringStream);
begin
  Connection.ReadStream(Dest, Message.ContentLength);

  // Roll back the stream to just before the message body!
  Dest.Seek(-Message.ContentLength, soFromCurrent);
end;

procedure TIdSipTcpServer.ReadMessage(Connection: TIdTCPConnection;
                                      Dest: TStringStream);
const
  CrLf = #$D#$A;
begin
  // We skip any leading CRLFs, and read up to (and including) the first blank
  // line.
  while (Dest.DataString = '') do
    Connection.Capture(Dest, '');

  // Capture() returns up to the blank line, but eats it: we add it back in
  // manually.
  Dest.Write(CrLf, Length(CrLf));
  Dest.Seek(0, soFromBeginning);
end;

procedure TIdSipTcpServer.ReturnInternalServerError(Connection: TIdTCPConnection;
                                                    const Reason: String);
var
  Res: TIdSipResponse;
begin
  Res := TIdSipResponse.Create;
  try
    // We really can't do much more than this.
    Res.StatusCode := SIPInternalServerError;
    Res.StatusText := Reason;
    Res.SipVersion := SipVersion;

    Self.WriteMessage(Connection, Res);
  finally
    Res.Free;
  end;
end;

procedure TIdSipTcpServer.ScheduleExceptionNotification(ExceptionType: ExceptClass;
                                                        const Reason: String);
var
  Ex: TIdSipExceptionWait;
begin
  Ex := TIdSipExceptionWait.Create;
  Ex.Event         := Self.DoOnException;
  Ex.ExceptionType := ExceptionType;
  Ex.Reason        := Reason;
  Self.Timer.AddEvent(TriggerImmediately, Ex);
end;

procedure TIdSipTcpServer.ScheduleReceivedMessage(Msg: TIdSipMessage;
                                                  ReceivedFrom: TIdSipConnectionBindings);
var
  RecvWait: TIdSipReceiveTCPMessageWait;
begin
  RecvWait := TIdSipReceiveTCPMessageWait.Create;
  RecvWait.Event        := Self.DoOnReceiveMessage;
  RecvWait.Message      := Msg.Copy;
  RecvWait.ReceivedFrom := ReceivedFrom;

  Self.Timer.AddEvent(TriggerImmediately, RecvWait);
end;

procedure TIdSipTcpServer.WriteMessage(Connection: TIdTCPConnection;
                                       AMessage: TIdSipMessage);
begin
  Connection.Write(AMessage.AsString);
end;

end.
