{
  (c) 2006 Directorate of New Technologies, Royal National Institute for Deaf people (RNID)

  The RNID licence covers this unit. Read the licence at:
      http://www.ictrnid.org.uk/docs/gw/rnid_license.txt

  This unit contains code written by:
    * Frank Shearar
}
unit IdSipUdpTransport;

interface

uses
  Classes, IdSipLocator, IdSipMessage, IdSipTransport, IdSocketHandle,IdTimerQueue,
  IdUDPServer, SysUtils;

type
  TIdSipUdpServer = class;

  // I implement the User Datagram Protocol (RFC 768) connections for the SIP
  // stack.
  TIdSipUDPTransport = class(TIdSipTransport)
  private
    Transport: TIdSipUdpServer;
  protected
    procedure DestroyServer; override;
    function  GetBindings: TIdSocketHandles; override;
    procedure InstantiateServer; override;
    procedure SendRequest(R: TIdSipRequest;
                          Dest: TIdSipLocation); override;
    procedure SendResponse(R: TIdSipResponse;
                           Dest: TIdSipLocation); override;
    procedure SetTimer(Value: TIdTimerQueue); override;
  public
    class function GetTransportType: String; override;
    class function SrvPrefix: String; override;

    constructor Create; override;

    function  IsReliable: Boolean; override;
    function  IsRunning: Boolean; override;
    procedure ReceiveRequest(Request: TIdSipRequest;
                             ReceivedFrom: TIdSipConnectionBindings); override;
    procedure Start; override;
    procedure Stop; override;
  end;

  TIdSipUdpServer = class(TIdUDPServer)
  private
    fTransportID: String;
    fTimer:       TIdTimerQueue;
  protected
    procedure DoUDPRead(AData: TStream; ABinding: TIdSocketHandle); override;
    procedure NotifyOfException(E: Exception);
    procedure ReceiveMessageInTimerContext(Msg: TIdSipMessage;
                                           Binding: TIdSocketHandle); virtual;
  public
    constructor Create(AOwner: TComponent); override;

    property Timer:       TIdTimerQueue read fTimer write fTimer;
    property TransportID: String        read fTransportID write fTransportID;
  end;

  TIdSipUdpClient = class(TIdSipUdpServer)
  private
    fOnFinished: TNotifyEvent;

    procedure DoOnFinished;
  protected
    procedure ReceiveMessageInTimerContext(Msg: TIdSipMessage;
                                           Binding: TIdSocketHandle); override;
  public
    property OnFinished: TNotifyEvent read fOnFinished write fOnFinished;
  end;

implementation

uses
  IdSipDns;

//******************************************************************************
//* TIdSipUDPTransport                                                         *
//******************************************************************************
//* TIdSipUDPTransport Public methods ******************************************

class function TIdSipUDPTransport.GetTransportType: String;
begin
  Result := UdpTransport;
end;

class function TIdSipUDPTransport.SrvPrefix: String;
begin
  Result := SrvUdpPrefix;
end;

constructor TIdSipUDPTransport.Create;
begin
  inherited Create;

  Self.Bindings.Add;
end;

function TIdSipUDPTransport.IsReliable: Boolean;
begin
  Result := false;
end;

function TIdSipUDPTransport.IsRunning: Boolean;
begin
  Result := Self.Transport.Active;
end;

procedure TIdSipUDPTransport.ReceiveRequest(Request: TIdSipRequest;
                                            ReceivedFrom: TIdSipConnectionBindings);
begin
  // RFC 3581 section 4
  if Request.LastHop.HasRPort then begin
    if not Request.LastHop.HasReceived then
      Request.LastHop.Received := ReceivedFrom.PeerIP;

    Request.LastHop.RPort := ReceivedFrom.PeerPort;
  end;

  inherited ReceiveRequest(Request, ReceivedFrom);
end;

procedure TIdSipUDPTransport.Start;
begin
  inherited Start;

  Self.Transport.Active := true;
end;

procedure TIdSipUDPTransport.Stop;
begin
  Self.Transport.Active := false;
end;

//* TIdSipUDPTransport Protected methods ***************************************

procedure TIdSipUDPTransport.DestroyServer;
begin
  Self.Transport.Free;
end;

function TIdSipUDPTransport.GetBindings: TIdSocketHandles;
begin
  Result := Self.Transport.Bindings;
end;

procedure TIdSipUDPTransport.InstantiateServer;
begin
  Self.Transport := TIdSipUdpServer.Create(nil);
  Self.Transport.ThreadedEvent := true;
  Self.Transport.TransportID := Self.ID;
end;

procedure TIdSipUDPTransport.SendRequest(R: TIdSipRequest;
                                         Dest: TIdSipLocation);
begin
  inherited SendRequest(R, Dest);

  Self.Transport.Send(Dest.IPAddress,
                      Dest.Port,
                      R.AsString);
end;

procedure TIdSipUDPTransport.SendResponse(R: TIdSipResponse;
                                          Dest: TIdSipLocation);
begin
  inherited SendResponse(R, Dest);

  // cf RFC 3581 section 4.
  // TODO: this isn't quite right. We have to send the response (if that's what
  // the message is) from the ip/port that the request was received on.

  Self.Transport.Send(Dest.IPAddress,
                      Dest.Port,
                      R.AsString);
end;

procedure TIdSipUDPTransport.SetTimer(Value: TIdTimerQueue);
begin
  inherited SetTimer(Value);

  Self.Transport.Timer := Value;
end;

//******************************************************************************
//* TIdSipUdpServer                                                            *
//******************************************************************************
//* TIdSipUdpServer Public methods *********************************************

constructor TIdSipUdpServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  Self.DefaultPort   := TIdSipTransportRegistry.DefaultPortFor(UdpTransport);
  Self.ThreadedEvent := true;
end;

//* TIdSipUdpServer Protected methods ******************************************

procedure TIdSipUdpServer.DoUDPRead(AData: TStream; ABinding: TIdSocketHandle);
var
  Msg: TIdSipMessage;
begin
  // Note that if AData contains a fragment of a message we don't care to
  // reassemble the packet. RFC 3261 section 18.3 tells us:

  //   If the transport packet ends before the end of the
  //   message body, this is considered an error.  If the message is a
  //   response, it MUST be discarded.  If the message is a request, the
  //   element SHOULD generate a 400 (Bad Request) response.  If the message
  //   has no Content-Length header field, the message body is assumed to
  //   end at the end of the transport packet.

  inherited DoUDPRead(AData, ABinding);

  try
    Msg := TIdSipMessage.ReadMessageFrom(AData);
    try
      Msg.ReadBody(AData);

      Self.ReceiveMessageInTimerContext(Msg, ABinding);
    finally
      Msg.Free;
    end;
  except
    on E: Exception do begin
      Self.NotifyOfException(E);
    end;
  end;
end;

procedure TIdSipUdpServer.NotifyOfException(E: Exception);
var
  Ex: TIdSipMessageExceptionWait;
begin
  Ex := TIdSipMessageExceptionWait.Create;
  Ex.ExceptionMessage := E.Message;
  Ex.Reason           := E.Message;
  Ex.TransportID      := Self.TransportID;

  Self.Timer.AddEvent(TriggerImmediately, Ex);
end;

procedure TIdSipUdpServer.ReceiveMessageInTimerContext(Msg: TIdSipMessage;
                                                       Binding: TIdSocketHandle);
var
  Wait: TIdSipReceiveMessageWait;
begin
  Wait := TIdSipReceiveMessageWait.Create;
  Wait.Message   := Msg.Copy;

  Wait.ReceivedFrom := TIdSipConnectionBindings.Create;
  Wait.ReceivedFrom.LocalIP   := Binding.IP;
  Wait.ReceivedFrom.LocalPort := Binding.Port;
  Wait.ReceivedFrom.PeerIP    := Binding.PeerIP;
  Wait.ReceivedFrom.PeerPort  := Binding.PeerPort;
  Wait.TransportID            := Self.TransportID;

  Self.Timer.AddEvent(TriggerImmediately, Wait);
end;

//******************************************************************************
//* TIdSipUdpClient                                                            *
//******************************************************************************
//* TIdSipUdpClient Protected methods ******************************************

procedure TIdSipUdpClient.ReceiveMessageInTimerContext(Msg: TIdSipMessage;
                                                       Binding: TIdSocketHandle);
begin
  inherited ReceiveMessageInTimerContext(Msg, Binding);

  if Msg.IsResponse and (Msg as TIdSipResponse).IsFinal then Self.DoOnFinished;
end;

//* TIdSipUdpClient Private methods ********************************************

procedure TIdSipUdpClient.DoOnFinished;
begin
  if Assigned(Self.OnFinished)
    then Self.OnFinished(Self);
end;

end.