{
  (c) 2005 Directorate of New Technologies, Royal National Institute for Deaf people (RNID)

  The RNID licence covers this unit. Read the licence at:
      http://www.ictrnid.org.uk/docs/gw/rnid_license.txt

  This unit contains code written by:
    * Frank Shearar
}
unit IdSipUserAgent;

interface

uses
  Contnrs, Classes, IdNotification, IdRoutingTable, IdSipAuthentication,
  IdSipCore, IdSipInviteModule, IdSipOptionsModule, IdSipMessage,
  IdSipRegistration, IdSipTransaction, IdSipTransport, IdTimerQueue;

type
  TIdSipUserAgent = class;

  TIdSipUserAgent = class(TIdSipAbstractCore,
                          IIdSipInviteModuleListener,
                          IIdSipActionListener,
                          IIdSipRegistrationListener)
  private
    ContactClosestToRegistrar: TIdSipContactHeader;
    Registrar:                 TIdSipUri;
    fDoNotDisturbMessage:      String;
    fHasProxy:                 Boolean;
    fProxy:                    TIdSipUri;
    fRegisterModule:           TIdSipOutboundRegisterModule;
    fInviteModule:             TIdSipInviteModule;
    HasRegistered:             Boolean;

    function  GetDoNotDisturb: Boolean;
    function  GetInitialResendInterval: Cardinal;
    function  GetProgressResendInterval: Cardinal;
    procedure OnAuthenticationChallenge(Action: TIdSipAction;
                                        Challenge: TIdSipResponse);
    procedure OnFailure(RegisterAgent: TIdSipOutboundRegistrationBase;
                        ErrorCode: Cardinal;
                        const Reason: String);
    procedure OnInboundCall(UserAgent: TIdSipInviteModule;
                            Session: TIdSipInboundSession);
    procedure OnNetworkFailure(Action: TIdSipAction;
                               ErrorCode: Cardinal;
                               const Reason: String);
    procedure OnSuccess(RegisterAgent: TIdSipOutboundRegistrationBase;
                        CurrentBindings: TIdSipContacts);
    procedure SetDoNotDisturb(Value: Boolean);
    procedure SetInitialResendInterval(Value: Cardinal);
    procedure SetProgressResendInterval(Value: Cardinal);
    procedure SetProxy(Value: TIdSipUri);
  public
    constructor Create; override;
    destructor  Destroy; override;

    procedure AddLocalHeaders(OutboundRequest: TIdSipRequest); override;
    function  AddOutboundAction(ActionType: TIdSipActionClass): TIdSipAction; override;
    procedure AddTransportListener(Listener: IIdSipTransportListener);
    procedure RemoveTransportListener(Listener: IIdSipTransportListener);
    function  RegisterWith(Registrar: TIdSipUri): TIdSipOutboundRegistration;
    function  ResponseForInvite: Cardinal; override;
    function  SessionCount: Integer;
    function  UnregisterFrom(Registrar: TIdSipUri): TIdSipOutboundUnregistration;

    property DoNotDisturb:           Boolean                      read GetDoNotDisturb write SetDoNotDisturb;
    property DoNotDisturbMessage:    String                       read fDoNotDisturbMessage write fDoNotDisturbMessage;
    property HasProxy:               Boolean                      read fHasProxy write fHasProxy;
    property InitialResendInterval:  Cardinal                     read GetInitialResendInterval write SetInitialResendInterval;
    property InviteModule:           TIdSipInviteModule           read fInviteModule;
    property ProgressResendInterval: Cardinal                     read GetProgressResendInterval write SetProgressResendInterval;
    property Proxy:                  TIdSipUri                    read fProxy write SetProxy;
    property RegisterModule:         TIdSipOutboundRegisterModule read fRegisterModule;
  end;

  TIdSipPendingLocalResolutionAction = class;

  // Given a configuration file, I create a stack.
  // The configuration file consists of lines. Each line is a complete and
  // independent setting consisting of a Directive, at least one space, and the
  // settings for that Directive.
  //
  // Here's a summary of the formats for each directive:
  //   Contact: sip:wintermute@tessier-ashpool.co.luna
  //   From: "Count Zero" <sip:countzero@jammer.org>
  //   HostName: talkinghead1.tessier-ashpool.co.luna
  //   HostName: 192.168.1.1
  //   Listen: <transport name><SP><host|IPv4 address|IPv6 reference|AUTO>:<port>
  //   Listen: UDP AUTO
  //   Listen: UDP 127.0.0.1
  //   Listen: TCP [::1]:5060
  //   MappedRoute: <route>/<netmask|number of bits><SP><gateway>[<SP><port>]
  //   MappedRoute: 192.168.0.0/16 192.168.1.1 5060
  //   MappedRoute: 192.168.0.0/255.255.255.0 192.168.1.1
  //   MappedRoute: ::/0 2002:deca:fbad::1 15060
  //   NameServer: <domain name or IP>:<port>
  //   NameServer: MOCK [;ReturnOnlySpecifiedRecords]
  //   Register: <SIP/S URI>
  //   ResolveNamesLocallyFirst: <true|TRUE|yes|YES|on|ON|1|false|FALSE|no|NO|off|OFF|0>
  //   RoutingTable: MOCK
  //   Proxy: <SIP/S URI>
  //   SupportEvent: refer
  //   InstanceID: urn:uuid:00000000-0000-0000-0000-000000000000
  //   UseGruu: <true|TRUE|yes|YES|on|ON|1|false|FALSE|no|NO|off|OFF|0>
  //
  // We try keep the configuration as order independent as possible. To
  // accomplish this, directives are sometimes marked as pending (by putting
  // objects in the PendingActions list in UpdateConfiguration). Some pending
  // actions involve sending SIP messages (like REGISTERs). Others configure the
  // stack that must only happen after other directives have been processed
  // (like ResolveNamesLocallyFirst, which must happen after processing the
  // NameServer directive). All pending actions that modify the stack
  // configuration are always processed BEFORE message-sending pending actions.
  TIdSipStackConfigurator = class(TObject)
  private
    FalseValues:             TStrings;
    FirstTransportDirective: Boolean;

    procedure AddAddress(UserAgent: TIdSipAbstractCore;
                         AddressHeader: TIdSipAddressHeader;
                         const AddressLine: String);
    procedure AddAuthentication(UserAgent: TIdSipAbstractCore;
                                const AuthenticationLine: String);
    procedure AddAutoAddress(AddressHeader: TIdSipAddressHeader);
    procedure AddFrom(UserAgent: TIdSipAbstractCore;
                      const FromLine: String);
    procedure AddHostName(UserAgent: TIdSipAbstractCore;
                      const HostNameLine: String);
    procedure AddLocator(UserAgent: TIdSipAbstractCore;
                         const NameServerLine: String);
    procedure AddMappedRoute(UserAgent: TIdSipAbstractCore;
                             const MappedRouteLine: String;
                             PendingActions: TObjectList);
    procedure AddPendingConfiguration(PendingActions: TObjectList;
                                      Action: TIdSipPendingLocalResolutionAction);
    procedure AddPendingMessageSend(PendingActions: TObjectList;
                                    Action: TIdSipAction);
    procedure AddPendingUnregister(UserAgent: TIdSipUserAgent;
                                   PendingActions: TObjectList);
    procedure AddProxy(UserAgent: TIdSipUserAgent;
                       const ProxyLine: String);
    procedure AddRoutingTable(UserAgent: TIdSipAbstractCore;
                              const RoutingTableLine: String);
    procedure AddSupportForEventPackage(UserAgent: TIdSipAbstractCore;
                                        const SupportEventLine: String);
    procedure AddTransport(Dispatcher: TIdSipTransactionDispatcher;
                           const TransportLine: String);
    procedure CheckUri(Uri: TIdSipUri;
                       const FailMsg: String);
    function  CreateLayers(Context: TIdTimerQueue): TIdSipUserAgent;
    procedure InstantiateMissingObjectsAsDefaults(UserAgent: TIdSipAbstractCore);
    procedure ParseFile(UserAgent: TIdSipUserAgent;
                        Configuration: TStrings;
                        PendingActions: TObjectList);
    procedure ParseLine(UserAgent: TIdSipUserAgent;
                        const ConfigurationLine: String;
                        PendingActions: TObjectList);
    procedure RegisterUA(UserAgent: TIdSipUserAgent;
                         const RegisterLine: String;
                         PendingActions: TObjectList);
    procedure UseGruu(UserAgent: TIdSipAbstractCore;
                      const UseGruuLine: String);
    procedure UseLocalResolution(UserAgent: TIdSipAbstractCore;
                                 const ResolveNamesLocallyFirstLine: String;
                                 PendingActions: TObjectList);
    procedure UserAgentName(UserAgent: TIdSipAbstractCore;
                      const UserAgentNameLine: String);
    procedure SendPendingActions(Actions: TObjectList);
    procedure SetInstanceID(UserAgent: TIdSipUserAgent;
                            const InstanceIDLine: String);
  public
    constructor Create;
    destructor  Destroy; override;

    function CreateUserAgent(Configuration: TStrings;
                             Context: TIdTimerQueue): TIdSipUserAgent; overload;
    function  StrToBool(B: String): Boolean;
    procedure UpdateConfiguration(UserAgent: TIdSipUserAgent;
                                  Configuration: TStrings);
  end;

  TIdSipPendingConfigurationAction = class(TObject)
  public
    procedure Execute; virtual; abstract;
  end;

  TIdSipPendingLocalResolutionAction = class(TIdSipPendingConfigurationAction)
  private
    fCore:                TIdSipAbstractCore;
    fResolveLocallyFirst: Boolean;
  public
    constructor Create(Core: TIdSipAbstractCore;
                       ResolveLocallyFirst: Boolean);

    procedure Execute; override;

    property Core:                TIdSipAbstractCore read fCore;
    property ResolveLocallyFirst: Boolean            read fResolveLocallyFirst;
  end;

  TIdSipPendingMappedRouteAction = class(TIdSipPendingConfigurationAction)
  private
    fCore:         TIdSipAbstractCore;
    fGateway:      String;
    fMappedPort:   Cardinal;
    fMask:         String;
    fNetwork:      String;
  public
    constructor Create(Core: TIdSipAbstractCore);

    procedure Execute; override;

    property Core:         TIdSipAbstractCore read fCore;
    property Gateway:      String             read fGateway write fGateway;
    property MappedPort:   Cardinal           read fMappedPort write fMappedPort;
    property Mask:         String             read fMask write fMask;
    property Network:      String             read fNetwork write fNetwork;
  end;

  TIdSipPendingMessageSend = class(TIdSipPendingConfigurationAction)
  private
    fAction: TIdSipAction;
  public
    constructor Create(Action: TIdSipAction);

    procedure Execute; override;

    property Action: TIdSipAction read fAction;
  end;

  TIdSipPendingRegistration = class(TIdSipPendingConfigurationAction)
  private
    fRegistrar: TIdSipUri;
    fUA:        TIdSipUserAgent;
  public
    constructor Create(UA: TIdSipUserAgent; Registrar: TIdSipUri);

    procedure Execute; override;

    property UA:        TIdSipUserAgent read fUA;
    property Registrar: TIdSipUri       read fRegistrar;

  end;

  TIdSipReconfigureStackWait = class(TIdWait)
  private
    fConfiguration: TStrings;
    fStack:         TIdSipUserAgent;

    procedure SetConfiguration(Value: TStrings);
  public
    constructor Create; override;
    destructor  Destroy; override;

    procedure Trigger; override;

    property Configuration: TStrings        read fConfiguration write SetConfiguration;
    property Stack:         TIdSipUserAgent read fStack write fStack;
  end;

// Configuration file constants
const
  AuthenticationDirective                 = 'Authentication';
  AutoKeyword                             = 'AUTO';
  ContactDirective                        = ContactHeaderFull;
  DebugMessageLogDirective                = 'DebugMessageLog';
  FromDirective                           = FromHeaderFull;
  HostNameDirective                       = 'HostName';
  InstanceIDDirective                     = 'InstanceID';
  ListenDirective                         = 'Listen';
  MockKeyword                             = 'MOCK';
  MappedRouteDirective                    = 'MappedRoute';
  NameServerDirective                     = 'NameServer';
  ProxyDirective                          = 'Proxy';
  RegisterDirective                       = 'Register';
  ResolveNamesLocallyFirstDirective       = 'ResolveNamesLocallyFirst';
  ReturnOnlySpecifiedRecordsLocatorOption = 'ReturnOnlySpecifiedRecords';
  RoutingTableDirective                   = 'RoutingTable';
  SupportEventDirective                   = 'SupportEvent';
  UseGruuDirective                        = 'UseGruu';
  UserAgentNameDirective                  = 'UserAgentName';

procedure EatDirective(var Line: String);

implementation

uses
  IdMockRoutingTable, IdSimpleParser, IdSipConsts, IdSipDns, IdSipIndyLocator,
  IdSipLocation, IdSipMockLocator, IdSipSubscribeModule, IdSystem, IdUnicode,
  SysUtils;

//******************************************************************************
//* Unit Public functions & procedures                                         *
//******************************************************************************

procedure EatDirective(var Line: String);
begin
  Fetch(Line, ':');
  Line := Trim(Line);
end;

//******************************************************************************
//* TIdSipUserAgent                                                            *
//******************************************************************************
//* TIdSipUserAgent Public methods *********************************************

constructor TIdSipUserAgent.Create;
begin
  inherited Create;

  Self.ContactClosestToRegistrar := TIdSipContactHeader.Create;
  Self.ContactClosestToRegistrar.IsUnset := true;
  Self.Registrar := TIdSipUri.Create;

  Self.fInviteModule   := Self.AddModule(TIdSipInviteModule) as TIdSipInviteModule;
  Self.fRegisterModule := Self.AddModule(TIdSipOutboundRegisterModule) as TIdSipOutboundRegisterModule;

  Self.InviteModule.AddListener(Self);

  Self.DoNotDisturb           := false;
  Self.DoNotDisturbMessage    := RSSIPTemporarilyUnavailable;
  Self.fProxy                 := TIdSipUri.Create('');
  Self.HasProxy               := false;
  Self.HasRegistered          := false;
  Self.InitialResendInterval  := DefaultT1;
end;

destructor TIdSipUserAgent.Destroy;
begin
  // Because we create TIdSipUserAgents from a StackConfigurator factory method,
  // we must clean up certain objects to which we have references, viz.,
  // Self.Dispatcher and Self.Authenticator.
  //
  // Thus we destroy these objects AFTER the inherited Destroy, because the base
  // class could well expect these objects to still exist.

  if Self.HasRegistered then
    Self.UnregisterFrom(Self.Registrar).Send;

  inherited Destroy;

  Self.Proxy.Free;
  Self.Dispatcher.Free;
  Self.Authenticator.Free;

  Self.Registrar.Free;
  Self.ContactClosestToRegistrar.Free;
end;

procedure TIdSipUserAgent.AddLocalHeaders(OutboundRequest: TIdSipRequest);
var
  LocalContact: TIdSipContactHeader;
begin
  inherited AddLocalHeaders(OutboundRequest);

  // draft-ietf-sip-gruu-10, section 8.1

  LocalContact := TIdSipContactHeader.Create;
  try
    if Self.ContactClosestToRegistrar.IsUnset then
      LocalContact.Value := Self.From.FullValue
    else
      LocalContact.Assign(Self.ContactClosestToRegistrar);

    LocalContact.IsGruu  := Self.UseGruu;
    LocalContact.IsUnset := Self.ContactClosestToRegistrar.IsUnset;

    OutboundRequest.AddHeader(LocalContact);
  finally
    LocalContact.Free;
  end;

  if OutboundRequest.HasSipsUri then
    OutboundRequest.FirstContact.Address.Scheme := SipsScheme;

  if Self.HasProxy then
    OutboundRequest.Route.AddRoute(Self.Proxy);
end;

function TIdSipUserAgent.AddOutboundAction(ActionType: TIdSipActionClass): TIdSipAction;
begin
  Result := inherited AddOutboundAction(ActionType);

  if not Self.ContactClosestToRegistrar.IsUnset then
    Result.LocalGruu := Self.ContactClosestToRegistrar;
end;

procedure TIdSipUserAgent.AddTransportListener(Listener: IIdSipTransportListener);
begin
  Self.Dispatcher.AddTransportListener(Listener);
end;

procedure TIdSipUserAgent.RemoveTransportListener(Listener: IIdSipTransportListener);
begin
  Self.Dispatcher.RemoveTransportListener(Listener);
end;

function TIdSipUserAgent.RegisterWith(Registrar: TIdSipUri): TIdSipOutboundRegistration;
var
  DefaultPort:      Cardinal;
  LocalAddress:     TIdSipLocation;
  Names:            TIdDomainNameRecords;
  RegistrarAddress: String;
begin
  LocalAddress := TIdSipLocation.Create;
  try
    if Registrar.IsSecure then
      DefaultPort := IdPORT_SIPS
    else
      DefaultPort := IdPORT_SIP;

    if TIdIPAddressParser.IsIPAddress(Registrar.Host) then
      RegistrarAddress := Registrar.Host
    else begin
      Names := TIdDomainNameRecords.Create;
      try
        Self.Locator.ResolveNameRecords(Registrar.Host, Names);

        if Names.IsEmpty then begin
          // Something's gone very wrong and we're about to try register to a
          // registrar that doesn't really exist!
          //
          // This isn't much of a solution. The only good reasons for doing this
          // are that (a) it doesn't do much harm (?) and (b) it allows us to
          // produce a meaningful Result, even if the result of Result.Send is
          // effectively a no-op.
          RegistrarAddress := '127.0.0.1';
        end
        else
          RegistrarAddress := Names[0].IPAddress;
      finally
        Names.Free;
      end;
    end;

    Self.RoutingTable.LocalAddressFor(RegistrarAddress, LocalAddress, DefaultPort);

    // We can only regard ContactClosestToRegistrar as "set" when we receive a
    // successful response to the REGISTER.
    Self.ContactClosestToRegistrar.DisplayName      := Self.From.DisplayName;
    Self.ContactClosestToRegistrar.Address.Scheme   := Registrar.Scheme;
    Self.ContactClosestToRegistrar.Address.Username := Self.From.Address.Username;
    Self.ContactClosestToRegistrar.Address.Host     := LocalAddress.IPAddress;
    Self.ContactClosestToRegistrar.Address.Port     := LocalAddress.Port;
    Self.ContactClosestToRegistrar.SipInstance      := Self.InstanceID;
    Self.HasRegistered := true;
  finally
    LocalAddress.Free;
  end;

  Self.Registrar.Uri := Registrar.Uri;

  Result := Self.RegisterModule.RegisterWith(Registrar, Self.ContactClosestToRegistrar);
  Result.AddListener(Self);
end;

function TIdSipUserAgent.ResponseForInvite: Cardinal;
begin
  // If we receive an INVITE (or an OPTIONS), what response code
  // would we return? If we don't wish to be disturbed, we return
  // SIPTemporarilyUnavailable; if we have no available lines, we
  // return SIPBusyHere, etc.

  if Self.DoNotDisturb then
    Result := SIPTemporarilyUnavailable
  else
    Result := inherited ResponseForInvite;
end;

function TIdSipUserAgent.SessionCount: Integer;
begin
  Result := Self.Actions.SessionCount;
end;

function TIdSipUserAgent.UnregisterFrom(Registrar: TIdSipUri): TIdSipOutboundUnregistration;
begin
  Result := Self.RegisterModule.UnregisterFrom(Registrar, Self.ContactClosestToRegistrar);
  Result.AddListener(Self);

  // This is technically incorrect: we should only set this when Result.Send is
  // invoked.
  Self.HasRegistered := false;
end;

//* TIdSipUserAgent Private methods ********************************************

function TIdSipUserAgent.GetDoNotDisturb: Boolean;
begin
  Result := Self.InviteModule.DoNotDisturb;
end;

function TIdSipUserAgent.GetInitialResendInterval: Cardinal;
begin
  Result := Self.InviteModule.InitialResendInterval;
end;

function TIdSipUserAgent.GetProgressResendInterval: Cardinal;
begin
  Result := Self.InviteModule.ProgressResendInterval;
end;

procedure TIdSipUserAgent.OnAuthenticationChallenge(Action: TIdSipAction;
                                                    Challenge: TIdSipResponse);
begin
  // Do nothing.
end;

procedure TIdSipUserAgent.OnFailure(RegisterAgent: TIdSipOutboundRegistrationBase;
                                    ErrorCode: Cardinal;
                                    const Reason: String);
begin
end;

procedure TIdSipUserAgent.OnInboundCall(UserAgent: TIdSipInviteModule;
                                        Session: TIdSipInboundSession);
begin
  // For now, do nothing.
end;

procedure TIdSipUserAgent.OnNetworkFailure(Action: TIdSipAction;
                                           ErrorCode: Cardinal;
                                           const Reason: String);
begin
  // Do nothing.
end;

procedure TIdSipUserAgent.OnSuccess(RegisterAgent: TIdSipOutboundRegistrationBase;
                                    CurrentBindings: TIdSipContacts);
var
  Gruu: String;
begin
  if Self.UseGruu then begin
    Gruu := CurrentBindings.GruuFor(Self.ContactClosestToRegistrar);

    if (Gruu <> '') then begin
      Self.ContactClosestToRegistrar.Address.Uri := Gruu;
      Self.ContactClosestToRegistrar.IsUnset     := false;
    end;
  end;
end;

procedure TIdSipUserAgent.SetDoNotDisturb(Value: Boolean);
begin
  Self.InviteModule.DoNotDisturb := Value;
end;

procedure TIdSipUserAgent.SetInitialResendInterval(Value: Cardinal);
begin
  Self.InviteModule.InitialResendInterval := Value;
end;

procedure TIdSipUserAgent.SetProgressResendInterval(Value: Cardinal);
begin
  Self.InviteModule.ProgressResendInterval := Value;
end;

procedure TIdSipUserAgent.SetProxy(Value: TIdSipUri);
begin
  Self.Proxy.Uri := Value.Uri;
end;

//******************************************************************************
//* TIdSipStackConfigurator                                                    *
//******************************************************************************
//* TIdSipStackConfigurator Public methods *************************************

constructor TIdSipStackConfigurator.Create;
begin
  inherited Create;

  Self.FalseValues := TStringList.Create;
  Self.FalseValues.Add('false');
  Self.FalseValues.Add('FALSE');
  Self.FalseValues.Add('no');
  Self.FalseValues.Add('NO');
  Self.FalseValues.Add('off');
  Self.FalseValues.Add('OFF');
  Self.FalseValues.Add('0');
end;

destructor TIdSipStackConfigurator.Destroy;
begin
  Self.FalseValues.Free;

  inherited Destroy;
end;

function TIdSipStackConfigurator.CreateUserAgent(Configuration: TStrings;
                                                 Context: TIdTimerQueue): TIdSipUserAgent;
begin
  try
    Result := Self.CreateLayers(Context);
    Self.UpdateConfiguration(Result, Configuration);
  except
    FreeAndNil(Result);

    raise;
  end;
end;

function TIdSipStackConfigurator.StrToBool(B: String): Boolean;
begin
  Result := Self.FalseValues.IndexOf(B) = ItemNotFoundIndex;
end;

procedure TIdSipStackConfigurator.UpdateConfiguration(UserAgent: TIdSipUserAgent;
                                                      Configuration: TStrings);
var
  PendingActions: TObjectList;
begin
  // Unregister if necessary (we've got a Registrar, and there's a different one in Configuration)
  // Update any settings in Configuration
  // Register to a new registrar if necessary

  Self.FirstTransportDirective := true;

//  UserAgent.Dispatcher.ClearTransports;

  PendingActions := TObjectList.Create(false);
  try
    Self.AddPendingUnregister(UserAgent, PendingActions);
    Self.ParseFile(UserAgent, Configuration, PendingActions);
    Self.InstantiateMissingObjectsAsDefaults(UserAgent);
    Self.SendPendingActions(PendingActions);
  finally
    PendingActions.Free;
  end;
end;

//* TIdSipStackConfigurator Private methods ************************************

procedure TIdSipStackConfigurator.AddAddress(UserAgent: TIdSipAbstractCore;
                                             AddressHeader: TIdSipAddressHeader;
                                             const AddressLine: String);
var
  Line: String;
begin
  Line := AddressLine;
  EatDirective(Line);

  if (Trim(Line) = AutoKeyword) then
    Self.AddAutoAddress(AddressHeader)
  else begin
    AddressHeader.Value := Line;

    if AddressHeader.IsMalformed then
      raise EParserError.Create(Format(MalformedConfigurationLine, [AddressLine]));
  end;
end;

procedure TIdSipStackConfigurator.AddAuthentication(UserAgent: TIdSipAbstractCore;
                                                    const AuthenticationLine: String);
var
  Line: String;
begin
  // See class comment for the format for this directive.
  Line := AuthenticationLine;
  EatDirective(Line);

  if IsEqual(Trim(Line), MockKeyword) then
    UserAgent.Authenticator := TIdSipMockAuthenticator.Create;
end;

procedure TIdSipStackConfigurator.AddAutoAddress(AddressHeader: TIdSipAddressHeader);
begin
  AddressHeader.DisplayName      := UTF16LEToUTF8(GetFullUserName);
  AddressHeader.Address.Username := UTF16LEToUTF8(GetUserName);
  AddressHeader.Address.Host     := LocalAddress;
end;

procedure TIdSipStackConfigurator.AddFrom(UserAgent: TIdSipAbstractCore;
                                          const FromLine: String);
begin
  // See class comment for the format for this directive.
  Self.AddAddress(UserAgent, UserAgent.From, FromLine);
end;

procedure TIdSipStackConfigurator.AddHostName(UserAgent: TIdSipAbstractCore;
                                              const HostNameLine: String);
var
  Line: String;
begin
  // See class comment for the format for this directive.

  Line := HostNameLine;
  EatDirective(Line);

  UserAgent.HostName := Line;
end;

procedure TIdSipStackConfigurator.AddLocator(UserAgent: TIdSipAbstractCore;
                                             const NameServerLine: String);
var
  Host: String;
  Line: String;
  Loc:  TIdSipIndyLocator;
  Port: String;
begin
  // See class comment for the format for this directive.
  Line := NameServerLine;
  EatDirective(Line);

  Host := Fetch(Line, [':', ';']);

  if Assigned(UserAgent.Locator) then begin
    UserAgent.Locator.Free;
    UserAgent.Locator := nil;
    UserAgent.Dispatcher.Locator := nil;
  end;

  if IsEqual(Host, MockKeyword) then begin
    UserAgent.Locator := TIdSipMockLocator.Create;

    if (Line <> '') then begin
      // There are additional configuration options for the mock locator to
      // process:

      (UserAgent.Locator as TIdSipMockLocator).ReturnOnlySpecifiedRecords := IsEqual(Line, ReturnOnlySpecifiedRecordsLocatorOption);
    end;
  end
  else begin
    Port := Fetch(Line, [' ', ';']);
    if not TIdSimpleParser.IsNumber(Port) then
      raise EParserError.Create(Format(MalformedConfigurationLine, [NameServerLine]));

    Loc := TIdSipIndyLocator.Create;
    Loc.NameServer          := Host;
    Loc.Port                := StrToInt(Port);

    UserAgent.Locator := Loc;
  end;

  UserAgent.Dispatcher.Locator := UserAgent.Locator;
end;

procedure TIdSipStackConfigurator.AddMappedRoute(UserAgent: TIdSipAbstractCore;
                                                 const MappedRouteLine: String;
                                                 PendingActions: TObjectList);
var
  MappedPort:        Cardinal;
  Gateway:           String;
  Line:              String;
  MappedRouteAction: TIdSipPendingMappedRouteAction;
  Mask:              String;
  Network:           String;
  Port:              String;
  Route:             String;
begin
  Line := MappedRouteLine;
  EatDirective(Line);

  Route   := Fetch(Line, ' ');
  Gateway := Fetch(Line, ' ');
  Port    := Line;

  Network := Fetch(Route, '/');
  Mask    := Route;

  // If IsNumber returns true then the route is something like "192.168.0.0/24".
  // Otherwise the route is something like "192.168.0.0/255.255.255.0".
  if TIdSimpleParser.IsNumber(Mask) then begin
    Mask := TIdIPAddressParser.MaskToAddress(StrToInt(Mask), TIdIPAddressParser.IPVersion(Network));
  end;

  // If there's no port, default to the SIP port.
  if (Port = '') then
    MappedPort := TIdSipTransportRegistry.DefaultPortFor(TcpTransport)
  else
    MappedPort := StrToInt(Port);

  MappedRouteAction := TIdSipPendingMappedRouteAction.Create(UserAgent);
  MappedRouteAction.Network      := Network;
  MappedRouteAction.Mask         := Mask;
  MappedRouteAction.Gateway      := Gateway;
  MappedRouteAction.MappedPort   := MappedPort;
  PendingActions.Add(MappedRouteAction);
end;

procedure TIdSipStackConfigurator.AddPendingConfiguration(PendingActions: TObjectList;
                                                          Action: TIdSipPendingLocalResolutionAction);
begin
  PendingActions.Insert(0, Action);
end;

procedure TIdSipStackConfigurator.AddPendingMessageSend(PendingActions: TObjectList;
                                                        Action: TIdSipAction);
var
  Pending: TIdSipPendingMessageSend;
begin
  Pending := TIdSipPendingMessageSend.Create(Action);
  PendingActions.Add(Pending);
end;

procedure TIdSipStackConfigurator.AddPendingUnregister(UserAgent: TIdSipUserAgent;
                                                       PendingActions: TObjectList);
var
  Reg: TIdSipOutboundRegisterModule;
begin
  Reg := UserAgent.RegisterModule;

  if Reg.HasRegistrar and not Reg.Registrar.IsMalformed then
    Self.AddPendingMessageSend(PendingActions, UserAgent.UnregisterFrom(Reg.Registrar));
end;

procedure TIdSipStackConfigurator.AddProxy(UserAgent: TIdSipUserAgent;
                                           const ProxyLine: String);
var
  Line: String;
begin
  // See class comment for the format for this directive.
  Line := ProxyLine;
  EatDirective(Line);

  UserAgent.HasProxy := true;

  UserAgent.Proxy.Uri := Trim(Line);

  Self.CheckUri(UserAgent.Proxy, Format(MalformedConfigurationLine, [ProxyLine]));
end;

procedure TIdSipStackConfigurator.AddRoutingTable(UserAgent: TIdSipAbstractCore;
                                                  const RoutingTableLine: String);
var
  Line: String;
begin
  // See class comment for the format for this directive.
  Line := RoutingTableLine;
  EatDirective(Line);

  if IsEqual(Line, MockKeyword) then
    UserAgent.RoutingTable := TIdMockRoutingTable.Create
  else begin
    // TODO: This needs to determine the platform for which we're compiling (Windows,
    // FreeBSD, whatever), and instantiate the appropriate routing table.
    UserAgent.RoutingTable := TIdWindowsRoutingTable.Create;
  end;

  UserAgent.Dispatcher.RoutingTable := UserAgent.RoutingTable;
end;

procedure TIdSipStackConfigurator.AddSupportForEventPackage(UserAgent: TIdSipAbstractCore;
                                                            const SupportEventLine: String);
var
  I:        Integer;
  Line:     String;
  Module:   TIdSipSubscribeModule;
  Packages: TStrings;
begin
  // See class comment for the format for this directive.
  if not UserAgent.UsesModule(TIdSipSubscribeModule) then
    Module := UserAgent.AddModule(TIdSipSubscribeModule) as TIdSipSubscribeModule
  else
    Module := UserAgent.ModuleFor(MethodSubscribe) as TIdSipSubscribeModule;

  Line := SupportEventLine;
  EatDirective(Line);

  Module.RemoveAllPackages;

  Packages := TStringList.Create;
  try
    Packages.CommaText := Line;

    for I := 0 to Packages.Count - 1 do
      Module.AddPackage(Packages[I]);
  finally
    Packages.Free;
  end;
end;

procedure TIdSipStackConfigurator.AddTransport(Dispatcher: TIdSipTransactionDispatcher;
                                               const TransportLine: String);
var
  HostAndPort: TIdSipHostAndPort;
  Line:        String;
  Transport:   String;
begin
  // See class comment for the format for this directive.
  Line := TransportLine;

  // If the configuration file contains any Listen directives, make sure we
  // clear all existing transports.
  if Self.FirstTransportDirective then begin
    Dispatcher.StopAllTransports;
    Dispatcher.ClearTransports;
    Self.FirstTransportDirective := false;
  end;

  EatDirective(Line);
  Transport := Fetch(Line, ' ');

  HostAndPort := TIdSipHostAndPort.Create;
  try
    HostAndPort.Value := Line;

    if (HostAndPort.Host = AutoKeyword) then
      HostAndPort.Host := LocalAddress;

    Dispatcher.AddTransportBinding(Transport, HostAndPort.Host, HostAndPort.Port);
  finally
    HostAndPort.Free;
  end;
end;

procedure TIdSipStackConfigurator.CheckUri(Uri: TIdSipUri;
                                           const FailMsg: String);
begin
  if not TIdSimpleParser.IsFQDN(Uri.Host)
    and not TIdIPAddressParser.IsIPv4Address(Uri.Host)
    and not TIdIPAddressParser.IsIPv6Reference(Uri.Host) then
    raise EParserError.Create(FailMsg);
end;

function TIdSipStackConfigurator.CreateLayers(Context: TIdTimerQueue): TIdSipUserAgent;
begin
  Result := TIdSipUserAgent.Create;
  Result.Timer := Context;
  Result.Dispatcher := TIdSipTransactionDispatcher.Create(Result.Timer, nil);
end;

procedure TIdSipStackConfigurator.InstantiateMissingObjectsAsDefaults(UserAgent: TIdSipAbstractCore);
begin
  if not Assigned(UserAgent.Authenticator) then
    UserAgent.Authenticator := TIdSipAuthenticator.Create;

  if not Assigned(UserAgent.Locator) then
    UserAgent.Locator := TIdSipIndyLocator.Create;

  if not Assigned(UserAgent.RoutingTable) then begin
    UserAgent.RoutingTable := TIdWindowsRoutingTable.Create;
    UserAgent.Dispatcher.RoutingTable := UserAgent.RoutingTable;
  end;

  if UserAgent.UsingDefaultFrom then
    Self.AddAutoAddress(UserAgent.From);
end;

procedure TIdSipStackConfigurator.ParseFile(UserAgent: TIdSipUserAgent;
                                            Configuration: TStrings;
                                            PendingActions: TObjectList);
var
  I: Integer;
begin
  for I := 0 to Configuration.Count - 1 do
    Self.ParseLine(UserAgent, Configuration[I], PendingActions);
end;

procedure TIdSipStackConfigurator.ParseLine(UserAgent: TIdSipUserAgent;
                                            const ConfigurationLine: String;
                                            PendingActions: TObjectList);
var
  FirstToken: String;
  Line:       String;
begin
  Line := ConfigurationLine;
  FirstToken := Trim(Fetch(Line, ':', false));

  if      IsEqual(FirstToken, AuthenticationDirective) then
    Self.AddAuthentication(UserAgent, ConfigurationLine)
  else if IsEqual(FirstToken, FromDirective) then
    Self.AddFrom(UserAgent, ConfigurationLine)
  else if IsEqual(FirstToken, HostNameDirective) then
    Self.AddHostName(UserAgent, ConfigurationLine)
  else if IsEqual(FirstToken, InstanceIDDirective) then
    Self.SetInstanceID(UserAgent, ConfigurationLine)
  else if IsEqual(FirstToken, ListenDirective) then
    Self.AddTransport(UserAgent.Dispatcher, ConfigurationLine)
  else if IsEqual(FirstToken, MappedRouteDirective) then
    Self.AddMappedRoute(UserAgent, ConfigurationLine, PendingActions)
  else if IsEqual(FirstToken, NameServerDirective) then
    Self.AddLocator(UserAgent, ConfigurationLine)
  else if IsEqual(FirstToken, ProxyDirective) then
    Self.AddProxy(UserAgent,  ConfigurationLine)
  else if IsEqual(FirstToken, RegisterDirective) then
    Self.RegisterUA(UserAgent, ConfigurationLine, PendingActions)
  else if IsEqual(FirstToken, ResolveNamesLocallyFirstDirective) then
    Self.UseLocalResolution(UserAgent, ConfigurationLine, PendingActions)
  else if IsEqual(FirstToken, RoutingTableDirective) then
    Self.AddRoutingTable(UserAgent, ConfigurationLine)
  else if IsEqual(FirstToken, SupportEventDirective) then
    Self.AddSupportForEventPackage(UserAgent, ConfigurationLine)
  else if IsEqual(FirstToken, UseGruuDirective) then
    Self.UseGruu(UserAgent, ConfigurationLine)
  else if IsEqual(FirstToken, UserAgentNameDirective) then
    Self.UserAgentName(UserAgent, ConfigurationLine);
end;

procedure TIdSipStackConfigurator.RegisterUA(UserAgent: TIdSipUserAgent;
                                             const RegisterLine: String;
                                             PendingActions: TObjectList);
var
  Line:         String;
  Registrar:    TIdSipUri;
  Registration: TIdSipPendingRegistration;
begin
  // See class comment for the format for this directive.
  Line := RegisterLine;
  EatDirective(Line);

  Line := Trim(Line);

  Registrar := TIdSipUri.Create(Line);
  try
    Registration := TIdSipPendingRegistration.Create(UserAgent, Registrar);

    PendingActions.Add(Registration);
  finally
    Registrar.Free;
  end;
end;

procedure TIdSipStackConfigurator.UseGruu(UserAgent: TIdSipAbstractCore;
                                          const UseGruuLine: String);
var
  Line: String;

begin
  Line := UseGruuLine;
  EatDirective(Line);

  UserAgent.UseGruu := StrToBool(Line);
end;

procedure TIdSipStackConfigurator.UseLocalResolution(UserAgent: TIdSipAbstractCore;
                                                     const ResolveNamesLocallyFirstLine: String;
                                                     PendingActions: TObjectList);
var
  Line:    String;
  Pending: TIdSipPendingLocalResolutionAction;
begin
  // See class comment for the format for this directive.
  Line := ResolveNamesLocallyFirstLine;
  EatDirective(Line);

  Line := Trim(Line);

  Pending := TIdSipPendingLocalResolutionAction.Create(UserAgent, Self.StrToBool(Line));
  Self.AddPendingConfiguration(PendingActions, Pending);
end;

procedure TIdSipStackConfigurator.UserAgentName(UserAgent: TIdSipAbstractCore;
                                                const UserAgentNameLine: String);
var
  Line: String;
begin
  Line := UserAgentNameLine;
  EatDirective(Line);

  UserAgent.UserAgentName := Line;
end;

procedure TIdSipStackConfigurator.SendPendingActions(Actions: TObjectList);
var
  I: Integer;
begin
  for I := 0 to Actions.Count - 1 do
    (Actions[I] as TIdSipPendingConfigurationAction).Execute;
end;

procedure TIdSipStackConfigurator.SetInstanceID(UserAgent: TIdSipUserAgent;
                                                const InstanceIDLine: String);
var
  Line: String;
begin
  Line := InstanceIDLine;
  EatDirective(Line);

  UserAgent.InstanceID := Line;
end;

//******************************************************************************
//* TIdSipPendingLocalResolutionAction                                         *
//******************************************************************************
//* TIdSipPendingLocalResolutionAction Public methods **************************

constructor TIdSipPendingLocalResolutionAction.Create(Core: TIdSipAbstractCore;
                                                      ResolveLocallyFirst: Boolean);
begin
  inherited Create;

  Self.fCore                := Core;
  Self.fResolveLocallyFirst := ResolveLocallyFirst;
end;

procedure TIdSipPendingLocalResolutionAction.Execute;
var
  IndyLoc: TIdSipIndyLocator;
begin
  if (Self.Core.Locator is TIdSipIndyLocator) then begin
    IndyLoc := Self.Core.Locator as TIdSipIndyLocator;

    IndyLoc.ResolveLocallyFirst := Self.ResolveLocallyFirst;
  end;
end;

//******************************************************************************
//* TIdSipPendingMappedRouteAction                                             *
//******************************************************************************
//* TIdSipPendingMappedRouteAction Public methods ******************************

constructor TIdSipPendingMappedRouteAction.Create(Core: TIdSipAbstractCore);
begin
  inherited Create;

  Self.fCore := Core;
end;

procedure TIdSipPendingMappedRouteAction.Execute;
begin
  Self.Core.RoutingTable.AddMappedRoute(Self.Network, Self.Mask, Self.Gateway, Self.MappedPort);
end;

//******************************************************************************
//* TIdSipPendingMessageSend                                                   *
//******************************************************************************
//* TIdSipPendingMessageSend Public methods ************************************

constructor TIdSipPendingMessageSend.Create(Action: TIdSipAction);
begin
  inherited Create;

  Self.fAction := Action;
end;

procedure TIdSipPendingMessageSend.Execute;
begin
  Self.Action.Send;
end;

//******************************************************************************
//* TIdSipPendingRegistration                                                  *
//******************************************************************************
//* TIdSipPendingRegistration Public methods ***********************************

constructor TIdSipPendingRegistration.Create(UA: TIdSipUserAgent; Registrar: TIdSipUri);
begin
  inherited Create;

  Self.fRegistrar := TIdSipUri.Create(Registrar.Uri);
  Self.fUA        := UA;
end;

procedure TIdSipPendingRegistration.Execute;
var
  Reg: TIdSipOutboundRegisterModule;
begin
  Reg := Self.UA.RegisterModule;

  Reg.AutoReRegister := true;
  Reg.HasRegistrar := true;
  Reg.Registrar := Self.Registrar;

  Self.UA.RegisterWith(Self.Registrar).Send;
end;

//******************************************************************************
//* TIdSipReconfigureStackWait                                                 *
//******************************************************************************
//* TIdSipReconfigureStackWait Public methods **********************************

constructor TIdSipReconfigureStackWait.Create;
begin
  inherited Create;

  Self.fConfiguration := TStringList.Create;
end;

destructor TIdSipReconfigureStackWait.Destroy;
begin
  Self.fConfiguration.Free;

  inherited Destroy;
end;

procedure TIdSipReconfigureStackWait.Trigger;
var
  Configurator: TIdSipStackConfigurator;
begin
  Configurator := TIdSipStackConfigurator.Create;
  try
    Configurator.UpdateConfiguration(Self.Stack, Self.Configuration);
  finally
    Configurator.Free;
  end;
end;

//* TIdSipReconfigureStackWait Private methods *********************************

procedure TIdSipReconfigureStackWait.SetConfiguration(Value: TStrings);
begin
  Self.fConfiguration.Assign(Value);
end;

end.
