unit Spike;

interface

uses
  audioclasses, Classes, Contnrs, Controls, ExtCtrls, Forms, IdDTMFPanel,
  IdObservable, IdRTPDiagnostics, IdSipCore, IdRTP, IdSdp, IdSipMessage,
  IdSipTransaction, IdSipTransport, IdSocketHandle, IdTimerQueue, StdCtrls,
  SyncObjs, SysUtils;

type
  TrnidSpike = class(TForm,
                     IIdRTPDataListener,
                     IIdRTPListener,
                     IIdObserver,
                     IIdSipOptionsListener,
                     IIdSipRegistrationListener,
                     IIdSipSessionListener,
                     IIdSipTransportListener,
                     IIdSipTransportSendingListener,
                     IIdSipUserAgentListener)
    UiTimer: TTimer;
    Splitter1: TSplitter;
    IOPanel: TPanel;
    DebugPanel: TPanel;
    Log: TMemo;
    Panel1: TPanel;
    Label1: TLabel;
    SessionCounter: TLabel;
    Label2: TLabel;
    RTPDataCount: TLabel;
    Label3: TLabel;
    UDPDataCount: TLabel;
    TargetUri: TEdit;
    Invite: TButton;
    Bye: TButton;
    InputSplitter: TSplitter;
    UpperInput: TPanel;
    Splitter3: TSplitter;
    InputText: TMemo;
    TextTimer: TTimer;
    BasePort: TEdit;
    RegistrarUri: TEdit;
    LowerInput: TPanel;
    Splitter4: TSplitter;
    OutputText: TMemo;
    Unregister: TButton;
    Register: TButton;
    Options: TButton;
    UseAsProxy: TCheckBox;
    ContactUri: TEdit;
    Label4: TLabel;
    Label5: TLabel;
    UseLooseRouting: TCheckBox;
    procedure ByeClick(Sender: TObject);
    procedure FormKeyPress(Sender: TObject; var Key: Char);
    procedure InviteClick(Sender: TObject);
    procedure UiTimerTimer(Sender: TObject);
    procedure TextTimerTimer(Sender: TObject);
    procedure InputTextKeyPress(Sender: TObject; var Key: Char);
    procedure BasePortChange(Sender: TObject);
    procedure RegisterClick(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure UnregisterClick(Sender: TObject);
    procedure OptionsClick(Sender: TObject);
    procedure ContactUriChange(Sender: TObject);
    procedure UseAsProxyClick(Sender: TObject);
    procedure RegistrarUriChange(Sender: TObject);
  private
    CounterLock:    TCriticalSection;
    Lock:           TCriticalSection;
    TextLock:       TCriticalSection;

    AudioPlayer:    TAudioData;
    DataStore:      TStream;
    Dispatch:       TIdSipTransactionDispatcher;
    DTMFPanel:      TIdDTMFPanel;
    Gateway:        String; // the IP of the NATting gateway
    HistListener:   TIdRTPPayloadHistogram;
    HistogramPanel: TIdHistogramPanel;
    RTPByteCount:   Integer;
    RunningPort:    Cardinal;
    SendBuffer:     String;
    StopEvent:      TEvent;
    Transports:     TObjectList;
    UA:             TIdSipUserAgentCore;
    UDPByteCount:   Integer;

    function  AddTransport(TransportType: TIdSipTransportClass): TIdSipTransport;
    function  LocalSDP(const Address: String): String;
    procedure LogMessage(Msg: TIdSipMessage; Inbound: Boolean);
    procedure OnAuthenticationChallenge(Action: TIdSipAction;
                                        Response: TIdSipResponse;
                                        var Password: String);
    procedure OnChanged(Observed: TObject);
    procedure OnDroppedUnmatchedResponse(Response: TIdSipResponse;
                                         Receiver: TIdSipTransport);
    procedure OnEstablishedSession(Session: TIdSipSession);
    procedure OnEndedSession(Session: TIdSipSession;
                             const Reason: String);
    procedure OnException(E: Exception;
                          const Reason: String);
    procedure OnFailure(RegisterAgent: TIdSipOutboundRegistration;
                        CurrentBindings: TIdSipContacts;
                        const Reason: String); overload;
    procedure OnFailure(OptionsAgent: TIdSipOutboundOptions;
                        Response: TIdSipResponse;
                        const Reason: String); overload;
    procedure OnInboundCall(Session: TIdSipInboundSession);
    procedure OnModifiedSession(Session: TIdSipSession;
                                Invite: TIdSipRequest);
    procedure OnNewData(Data: TIdRTPPayload;
                        Binding: TIdSocketHandle);
    procedure OnRTCP(Packet: TIdRTCPPacket;
                     Binding: TIdSocketHandle);
    procedure OnRTP(Packet: TIdRTPPacket;
                    Binding: TIdSocketHandle);
    procedure OnPlaybackStopped(Origin: TAudioData);
    procedure OnReceiveRequest(Request: TIdSipRequest;
                               Transport: TIdSipTransport);
    procedure OnReceiveResponse(Response: TIdSipResponse;
                                Transport: TIdSipTransport);
    procedure OnRejectedMessage(const Msg: String;
                                const Reason: String);
    procedure OnSendRequest(Request: TIdSipRequest;
                            Transport: TIdSipTransport);
    procedure OnSendResponse(Response: TIdSipResponse;
                             Transport: TIdSipTransport);
    procedure OnSuccess(RegisterAgent: TIdSipOutboundRegistration;
                        CurrentBindings: TIdSipContacts); overload;
    procedure OnSuccess(OptionsAgent: TIdSipOutboundOptions;
                        Response: TIdSipResponse); overload;
    procedure ProcessPCM(Data: TStream);
    procedure ProcessText(Text: String);
    procedure ResetCounters;
    procedure StartTransports;
    procedure StopReadingData;
    procedure StopTransports;
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
  end;

const
  AudioFile = 'dump.wav';

var
  rnidSpike: TrnidSpike;

implementation

{$R *.dfm}

uses
  Dialogs, Graphics, IdGlobal, IdSipConsts, IdStack;

const
  LocalHostName = '127.0.0.1';

//******************************************************************************
//* TrnidSpike                                                                 *
//******************************************************************************
//* TrnidSpike Public methods **************************************************

constructor TrnidSpike.Create(AOwner: TComponent);
var
  Contact: TIdSipContactHeader;
  From:    TIdSipFromHeader;
begin
  inherited Create(AOwner);

//  Self.Gateway := GStack.LocalAddress;
  Self.Gateway := '80.168.137.82';

  Self.Transports := TObjectList.Create(true);
  Self.RunningPort := IdPORT_SIP;

  Self.DTMFPanel := TIdDTMFPanel.Create(nil);
  Self.DTMFPanel.Align  := alLeft;
  Self.DTMFPanel.Left   := -1; // Forces the panel left of the splitter
  Self.DTMFPanel.Parent := Self.UpperInput;
  Self.DTMFPanel.Top    := 0;

  Self.HistogramPanel := TIdHistogramPanel.Create(nil);
  Self.HistogramPanel.Align      := alLeft;
  Self.HistogramPanel.BevelInner := bvNone;
  Self.HistogramPanel.BevelOuter := bvNone;
  Self.HistogramPanel.Left       := -1; // Forces the panel left of the splitter
  Self.HistogramPanel.Parent     := Self.LowerInput;
  Self.HistogramPanel.Top        := 0;
  Self.HistogramPanel.Width      := Self.DTMFPanel.Width;

  Self.HistListener := TIdRTPPayloadHistogram.Create;
  Self.HistListener.AddObserver(Self.HistogramPanel);

  Self.Lock        := TCriticalSection.Create;
  Self.CounterLock := TCriticalSection.Create;
  Self.TextLock    := TCriticalSection.Create;

  Self.DataStore := TMemoryStream.Create;
  Self.AudioPlayer := TAudioData.Create;
  Self.AudioPlayer.AutoFreeSource := false;
  Self.AudioPlayer.OnStop := Self.OnPlaybackStopped;
  Self.AudioPlayer.SetFormatParameters(afMuLaw, ChannelsMono, 8000, 8);
  Self.AudioPlayer.Assign(Self.DataStore);

  Self.StopEvent := TSimpleEvent.Create;

  Self.Dispatch := TIdSipTransactionDispatcher.Create;
  Self.Dispatch.AddTransport(Self.AddTransport(TIdSipTCPTransport));
  Self.Dispatch.AddTransport(Self.AddTransport(TIdSipUDPTransport));

  Self.UA := TIdSipUserAgentCore.Create;
  Self.UA.Dispatcher := Self.Dispatch;
  Self.UA.AddUserAgentListener(Self);
  Self.UA.AddObserver(Self);
  Self.UA.HostName := (Self.Transports[0] as TIdSipTransport).HostName;
  Self.UA.UserAgentName := '';
  Self.UA.AddAllowedMethod(MethodRegister);

  Contact := TIdSipContactHeader.Create;
  try
    Contact.Value := 'sip:franks@'
                   + (Self.Transports[0] as TIdSipTransport).HostName + ':'
                   + IntToStr((Self.Transports[0] as TIdSipTransport).Bindings[0].Port);
    Self.UA.Contact := Contact;
  finally
    Contact.Free;
  end;

  From := TIdSipFromHeader.Create;
  try
    From.Value := 'sip:franks@' + (Self.Transports[0] as TIdSipTransport).HostName
                + ':' + IntToStr((Self.Transports[0] as TIdSipTransport).Bindings[0].Port);
    Self.UA.From := From;
  finally
    From.Free;
  end;

  try
    BasePort.Text := IntToStr((Self.Transports[0] as TIdSipTransport).Bindings[0].Port);
    Self.StartTransports;
  except
    on EIdCouldNotBindSocket do
      ShowMessage('Something''s hogged the SIP port '
                + '(' + IntToStr((Self.Transports[0] as TIdSipTransport).Bindings[0].Port) + ') - '
                + 'kill it and restart this');
  end;
  Self.UA.From.Value := 'sip:rnid01@' + Self.Gateway;
  Self.UA.HasProxy := Self.UseAsProxy.Checked;
  Self.UA.Proxy.Uri := Self.RegistrarUri.Text + ';lr';
end;

destructor TrnidSpike.Destroy;
begin
  Self.StopTransports;

  Self.UA.Free;
  Self.Dispatch.Free;

  Self.TextLock.Free;
  Self.CounterLock.Free;
  Self.Lock.Free;

  // If no data at all has arrived we stall here.
  Self.AudioPlayer.Stop;
  Self.StopEvent.WaitFor(1000);
  Self.AudioPlayer.Free;

  Self.DataStore.Free;
  Self.StopEvent.Free;

  Self.HistListener.Free;
  Self.HistogramPanel.Free;
  Self.DTMFPanel.Free;

  Self.Transports.Free;

  inherited Destroy;
end;

//* TrnidSpike Private methods *************************************************

function TrnidSpike.AddTransport(TransportType: TIdSipTransportClass): TIdSipTransport;
var
  Binding: TIdSocketHandle;
begin
  Result := TransportType.Create(IdPORT_SIP);
  Self.Transports.Add(Result);
  Result.HostName := Self.Gateway;

  if (GStack.LocalAddress <> LocalHostName) then begin
    Binding      := Result.Bindings.Add;
    Binding.IP   := GStack.LocalAddress;
    Binding.Port := RunningPort;
//    Result.HostName := Binding.IP;
  end;
//  else
//   Result.HostName := LocalHostName;

  Binding      := Result.Bindings.Add;
  Binding.IP   := LocalHostName;
  Binding.Port := RunningPort;
  Result.AddTransportListener(Self);
  Result.AddTransportSendingListener(Self);
end;

function TrnidSpike.LocalSDP(const Address: String): String;
begin
  Result := 'v=0'#13#10
          + 'o=franks 123456 123456 IN IP4 ' + Address + #13#10
          + 's=-'#13#10
          + 'c=IN IP4 ' + Address + #13#10
          + 't=0 0'#13#10
          + 'm=audio 8000 RTP/AVP 0'#13#10
          + 'm=audio 8002 RTP/AVP 96'#13#10
          + 'a=rtpmap:96 telephone-event/8000'#13#10
          + 'a=fmtp:101 0-16'#13#10
          + 'm=text 8004 RTP/AVP 97'#13#10
          + 'a=rtpmap:97 T140/1000'#13#10;
end;

procedure TrnidSpike.LogMessage(Msg: TIdSipMessage; Inbound: Boolean);
begin
  Self.Lock.Acquire;
  try
    if Inbound then
      Self.Log.Lines.Add('<<<< ' + FormatDateTime('yyyy/mm/dd hh:mm:ss.zzz', Now))
    else
      Self.Log.Lines.Add('>>>> ' + FormatDateTime('yyyy/mm/dd hh:mm:ss.zzz', Now));

    Self.Log.Lines.Add(Msg.AsString);
  finally
    Self.Lock.Release;
  end;
end;

procedure TrnidSpike.OnAuthenticationChallenge(Action: TIdSipAction;
                                               Response: TIdSipResponse;
                                               var Password: String);
begin
  Password := 'rnid01';
end;

procedure TrnidSpike.OnChanged(Observed: TObject);
begin
  Self.SessionCounter.Caption := IntToStr((Observed as TIdSipUserAgentCore).SessionCount);
end;

procedure TrnidSpike.OnDroppedUnmatchedResponse(Response: TIdSipResponse;
                                                Receiver: TIdSipTransport);
begin
  Self.Lock.Acquire;
  try
    Self.Log.Lines.Add('Dropped unmatched response: ' + Response.Description);
  finally
    Self.Lock.Release;
  end;
end;

procedure TrnidSpike.OnEstablishedSession(Session: TIdSipSession);
begin
end;

procedure TrnidSpike.OnEndedSession(Session: TIdSipSession;
                                    const Reason: String);
begin
  Self.Lock.Acquire;
  try
    Self.Log.Lines.Add('Session ended: ' + Reason);
  finally
    Self.Lock.Release;
  end;

  Self.AudioPlayer.Stop;
  Self.StopReadingData;
  Session.PayloadProcessor.RemoveDataListener(Self);
  Session.PayloadProcessor.RemoveRTPListener(Self.HistListener);
  Session.PayloadProcessor.RemoveDataListener(Self.DTMFPanel);
  Self.DTMFPanel.Processor := nil;
end;

procedure TrnidSpike.OnException(E: Exception;
                                 const Reason: String);
begin

  Self.Lock.Acquire;
  try
    Self.Log.Lines.Add('Exception ' + E.ClassName + ': ' + E.Message
                     + ' raised because: ''' + Reason + '''')
  finally
    Self.Lock.Release;
  end;
end;

procedure TrnidSpike.OnFailure(RegisterAgent: TIdSipOutboundRegistration;
                               CurrentBindings: TIdSipContacts;
                               const Reason: String);
begin
end;

procedure TrnidSpike.OnFailure(OptionsAgent: TIdSipOutboundOptions;
                               Response: TIdSipResponse;
                               const Reason: String);
begin
end;                               

procedure TrnidSpike.OnInboundCall(Session: TIdSipInboundSession);
var
  Address: String;
begin
  Self.ResetCounters;

  Session.AcceptCall(Self.LocalSDP(Self.Gateway),
                     SdpMimeType);

  Self.AudioPlayer.Play(AnyAudioDevice);
  Session.PayloadProcessor.AddRTPListener(Self.HistListener);
  Session.PayloadProcessor.AddRTPListener(Self);
  Session.PayloadProcessor.AddDataListener(Self);
  Session.PayloadProcessor.AddDataListener(Self.DTMFPanel);

  Self.DTMFPanel.Processor := Session.PayloadProcessor;
end;

procedure TrnidSpike.OnModifiedSession(Session: TIdSipSession;
                                       Invite: TIdSipRequest);
begin
end;

procedure TrnidSpike.OnNewData(Data: TIdRTPPayload;
                               Binding: TIdSocketHandle);
var
  S: TStringStream;
begin
  if (Lowercase(Data.Name) = Lowercase(PCMMuLawEncoding)) then begin
    S := TStringStream.Create((Data as TIdRTPRawPayload).Data);
    try
      Self.ProcessPCM(S);
    finally
      S.Free;
    end;
  end
  else if (Data is TIdRTPT140Payload) then begin
    Self.ProcessText((Data as TIdRTPT140Payload).Block);
  end;
end;

procedure TrnidSpike.OnRTCP(Packet: TIdRTCPPacket;
                            Binding: TIdSocketHandle);
begin
end;

procedure TrnidSpike.OnRTP(Packet: TIdRTPPacket;
                           Binding: TIdSocketHandle);
begin
  Self.CounterLock.Acquire;
  try
    Inc(Self.RTPByteCount, Packet.Payload.Length);
  finally
    Self.CounterLock.Release;
  end;
end;

procedure TrnidSpike.OnPlaybackStopped(Origin: TAudioData);
begin
  Self.StopEvent.SetEvent;
end;

procedure TrnidSpike.OnReceiveRequest(Request: TIdSipRequest;
                                      Transport: TIdSipTransport);
begin
  Self.LogMessage(Request, true);
end;

procedure TrnidSpike.OnReceiveResponse(Response: TIdSipResponse;
                                       Transport: TIdSipTransport);
begin
  Self.LogMessage(Response, true);
end;

procedure TrnidSpike.OnRejectedMessage(const Msg: String;
                                       const Reason: String);
begin
  Self.Lock.Acquire;
  try
    Self.Log.Lines.Add('----REJECTED MESSAGE: ' + Reason + '----');
    Self.Log.Lines.Add(Msg);
    Self.Log.Lines.Add('----');
  finally
    Self.Lock.Release;
  end;
end;

procedure TrnidSpike.OnSendRequest(Request: TIdSipRequest;
                                   Transport: TIdSipTransport);
begin
  Request.LastHop.SentBy := Self.Gateway;
  Self.LogMessage(Request, false);
end;

procedure TrnidSpike.OnSendResponse(Response: TIdSipResponse;
                                    Transport: TIdSipTransport);
begin
  Self.LogMessage(Response, false);
end;

procedure TrnidSpike.OnSuccess(RegisterAgent: TIdSipOutboundRegistration;
                               CurrentBindings: TIdSipContacts);
begin
end;

procedure TrnidSpike.OnSuccess(OptionsAgent: TIdSipOutboundOptions;
                               Response: TIdSipResponse);
begin
end;

procedure TrnidSpike.ProcessPCM(Data: TStream);
begin
  Self.AudioPlayer.Lock;
  try
    if Assigned(Self.DataStore) then begin
      Self.DataStore.Seek(0, soFromEnd);
      Self.DataStore.CopyFrom(Data, 0);
    end;
  finally
    Self.AudioPlayer.UnLock;
  end;
end;

procedure TrnidSpike.ProcessText(Text: String);
begin
  Self.TextLock.Acquire;
  try
    Self.OutputText.Text := Self.OutputText.Text + Text;
  finally
    Self.TextLock.Release;
 end;
end;

procedure TrnidSpike.ResetCounters;
begin
  Self.CounterLock.Acquire;
  try
    Self.Invite.Enabled := false;
    Self.RTPByteCount   := 0;
    Self.UDPByteCount   := 0;
  finally
    Self.CounterLock.Release;
  end;
end;

procedure TrnidSpike.StartTransports;
var
  I: Integer;
begin
  for I := 0 to Self.Transports.Count - 1 do
    (Self.Transports[I] as TIdSipTransport).Start;
end;

procedure TrnidSpike.StopReadingData;
begin
  Self.Invite.Enabled := true;
end;

procedure TrnidSpike.StopTransports;
var
  I: Integer;
begin
  for I := 0 to Self.Transports.Count - 1 do
    (Self.Transports[I] as TIdSipTransport).Stop;
end;

//* TrnidSpike Published methods ***********************************************

procedure TrnidSpike.ByeClick(Sender: TObject);
begin
  Self.UA.TerminateAllCalls;
  Self.StopReadingData;
end;

procedure TrnidSpike.InviteClick(Sender: TObject);
var
  Session: TIdSipSession;
  Target:  TIdSipToHeader;
begin
  Target := TIdSipToHeader.Create;
  try
    Target.Address.Uri := Self.TargetUri.Text;

    Self.ResetCounters;

    Session := Self.UA.Call(Target,
                            Self.LocalSDP(Self.Gateway),
                            SdpMimeType);

    Session.AddSessionListener(Self);
    Self.AudioPlayer.Play(AnyAudioDevice);
    Session.PayloadProcessor.AddRTPListener(Self.HistListener);
    Session.PayloadProcessor.AddDataListener(Self.DTMFPanel);
    Self.DTMFPanel.Processor := Session.PayloadProcessor;
    Session.PayloadProcessor.AddDataListener(Self);
  finally
    Target.Free;
  end;
end;

procedure TrnidSpike.FormKeyPress(Sender: TObject; var Key: Char);
begin
  //
end;

procedure TrnidSpike.UiTimerTimer(Sender: TObject);
begin
  Self.CounterLock.Acquire;
  try
    RTPDataCount.Caption := IntToStr(Self.RTPByteCount);
    UDPDataCount.Caption := IntToStr(Self.UDPByteCount);
  finally
    Self.CounterLock.Release;
  end;
end;

procedure TrnidSpike.TextTimerTimer(Sender: TObject);
//var
//  Text: TIdRTPT140Payload;
begin
{
  Self.TextLock.Acquire;
  try
    if (Self.SendBuffer <> '') then begin
      Text := Self.Media.Profile.EncodingFor(T140Encoding + '/' + IntToStr(T140ClockRate)).Clone as TIdRTPT140Payload;
      try
        Text.Block := Self.SendBuffer;
//        Self.Media.SessionFor(Text).SendData(Text);
      finally
        Text.Free;
      end;
      Self.SendBuffer := '';
    end;
  finally
    Self.TextLock.Release;
  end;
}
end;

procedure TrnidSpike.InputTextKeyPress(Sender: TObject; var Key: Char);
begin
  Self.TextLock.Acquire;
  try
    Self.SendBuffer := Self.SendBuffer + Key;
  finally
    Self.TextLock.Release;
  end;
end;

procedure TrnidSpike.BasePortChange(Sender: TObject);
var
  I, J:    Integer;
  NewPort: Integer;
begin
  Self.StopTransports;

  NewPort := StrToInt(BasePort.Text);

  for I := 0 to Self.Transports.Count - 1 do
    for J := 0 to (Self.Transports[I] as TIdSipTransport).Bindings.Count - 1 do
      (Self.Transports[I] as TIdSipTransport).Bindings[J].Port := NewPort;

  Self.UA.From.Address.Port := NewPort;

  Self.StartTransports;
end;

procedure TrnidSpike.RegisterClick(Sender: TObject);
var
  Registrar: TIdSipUri;
begin
  Registrar := TIdSipUri.Create(Self.RegistrarUri.Text);
  try
    Self.UA.RegisterWith(Registrar).AddListener(Self);
  finally
    Registrar.Free;
  end;
end;

procedure TrnidSpike.FormResize(Sender: TObject);
begin
  Self.UpperInput.Height := (Self.ClientHeight - Self.InputSplitter.Height) div 2;
end;

procedure TrnidSpike.UnregisterClick(Sender: TObject);
var
  Registrar: TIdSipUri;
begin
  Registrar := TIdSipUri.Create(Self.RegistrarUri.Text);
  try
    Self.UA.UnregisterFrom(Registrar).AddListener(Self);
  finally
    Registrar.Free;
  end;
end;

procedure TrnidSpike.OptionsClick(Sender: TObject);
var
  Dest: TIdSipAddressHeader;
begin
  Dest := TIdSipAddressHeader.Create;
  try
    Dest.Value := Self.TargetUri.Text;
    Self.UA.QueryOptions(Dest).AddListener(Self);
  finally
    Dest.Free;
  end;
end;

procedure TrnidSpike.ContactUriChange(Sender: TObject);
begin
  Self.UA.Contact.Value := Self.ContactUri.Text;
end;

procedure TrnidSpike.UseAsProxyClick(Sender: TObject);
begin
  Self.UA.HasProxy := Self.UseAsProxy.Checked;
end;

procedure TrnidSpike.RegistrarUriChange(Sender: TObject);
var
  Uri: String;
begin
  Uri := Self.RegistrarUri.Text;

  if Self.UseLooseRouting.Checked then
    Uri := Uri + ';lr';

  Self.UA.Proxy.Uri := Uri;
end;

end.
