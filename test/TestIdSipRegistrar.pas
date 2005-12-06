{
  (c) 2004 Directorate of New Technologies, Royal National Institute for Deaf people (RNID)

  The RNID licence covers this unit. Read the licence at:
      http://www.ictrnid.org.uk/docs/gw/rnid_license.txt

  This unit contains code written by:
    * Frank Shearar
}
unit TestIdSipRegistrar;

interface

uses
  IdSipCore, IdSipMessage, IdSipMockBindingDatabase,
  IdSipMockTransactionDispatcher, IdSipRegistration, TestFramework,
  TestFrameworkSip, TestFrameworkSipTU;

type
  // We test that the registrar returns the responses it should. The nitty
  // gritties of how the registrar preserves ACID properties, or the ins and
  // outs of actual database stuff don't interest us - look at
  // TestTIdSipAbstractBindingDatabase for that.
  TestTIdSipRegistrar = class(TTestCase)
  private
    DB:           TIdSipMockBindingDatabase;
    Dispatch:     TIdSipMockTransactionDispatcher;
    ExpireAll:    String;
    FirstContact: TIdSipContactHeader;
    Registrar:    TIdSipRegistrar;
    Request:      TIdSipRequest;

    procedure CheckResponse(Received: TIdSipContacts;
                            const Msg: String);
    procedure CheckServerReturned(ExpectedStatusCode: Cardinal;
                                  const Msg: String);
    procedure CheckServerReturnedOK(const Msg: String);
    procedure SimulateRemoteRequest;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestComplicatedRegistration;
    procedure TestDatabaseUpdatesBindings;
    procedure TestDatabaseGetsExpiry;
    procedure TestFailedBindingsFor;
    procedure TestFailedRemoveAll;
    procedure TestInvalidAddressOfRecord;
    procedure TestMethod;
    procedure TestOKResponseContainsAllBindings;
    procedure TestReceiveInvite;
    procedure TestReceiveRegister;
    procedure TestReceiveExpireTooShort;
    procedure TestReceiveExpireParamTooShort;
    procedure TestReceiveWildcard;
    procedure TestReceiveWildcardWithExtraContacts;
    procedure TestReceiveWildcardWithNonzeroExpiration;
    procedure TestRegisterAddsBindings;
    procedure TestRegisterAddsMultipleBindings;
    procedure TestRejectRegisterWithReplacesHeader;
    procedure TestUnauthorizedUser;
  end;

  TestTIdSipOutboundRegisterModule = class(TTestCaseTU)
  private
    Module:    TIdSipOutboundRegisterModule;
    RemoteUri: TIdSipURI;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCleanUpUnregisters;
    procedure TestCreateRegister;
    procedure TestCreateRegisterReusesCallIDForSameRegistrar;
    procedure TestReregister;
    procedure TestUnregisterFrom;
  end;

  TestTIdSipRegistration = class(TestTIdSipAction)
  private
    RegisterModule: TIdSipRegisterModule;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestIsRegistration; override;
  end;

  TestTIdSipInboundRegistration = class(TestTIdSipRegistration)
  private
    RegisterAction: TIdSipInboundRegistration;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestIsInbound; override;
    procedure TestIsInvite; override;
    procedure TestIsOptions; override;
    procedure TestIsRegistration; override;
    procedure TestIsSession; override;
  end;

  TestTIdSipOutboundRegistration = class(TestTIdSipRegistration,
                                         IIdSipRegistrationListener)
  private
    Contacts:   TIdSipContacts;
    MinExpires: Cardinal;
    Registrar:  TIdSipAbstractCore;
    Succeeded:  Boolean;

    procedure OnFailure(RegisterAgent: TIdSipOutboundRegistration;
                        CurrentBindings: TIdSipContacts;
                        Response: TIdSipResponse);
    procedure OnSuccess(RegisterAgent: TIdSipOutboundRegistration;
                        CurrentBindings: TIdSipContacts);
    procedure ReceiveRemoteIntervalTooBrief;
  protected
    function RegistrarAddress: TIdSipUri;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAddListener;
    procedure TestMethod;
    procedure TestReceiveFail;
    procedure TestReceiveIntervalTooBrief;
    procedure TestReceiveMovedPermanently;
    procedure TestReceiveOK;
    procedure TestRemoveListener;
    procedure TestReregisterTime;
    procedure TestSequenceNumberIncrements;
    procedure TestUsername;
  end;

  TExpiryProc = procedure(ExpiryTime: Cardinal) of object;

  TestTIdSipOutboundRegister = class(TestTIdSipOutboundRegistration)
  private
    procedure CheckAutoReregister(ReceiveResponse: TExpiryProc;
                                  EventIsScheduled: Boolean;
                                  const MsgPrefix: String);
    procedure ReceiveOkWithContactExpiresOf(ExpiryTime: Cardinal);
    procedure ReceiveOkWithExpiresOf(ExpiryTime: Cardinal);
    procedure ReceiveOkWithNoExpires(ExpiryTime: Cardinal);
  protected
    function  CreateAction: TIdSipAction; override;
  published
    procedure TestAutoReregister;
    procedure TestAutoReregisterContactHasExpires;
    procedure TestAutoReregisterNoExpiresValue;
    procedure TestAutoReregisterSwitchedOff;
    procedure TestReceiveIntervalTooBriefForOneContact;
    procedure TestRegister;
  end;

  TestTIdSipOutboundRegistrationQuery = class(TestTIdSipOutboundRegistration)
  protected
    function CreateAction: TIdSipAction; override;
  published
    procedure TestFindCurrentBindings;
  end;

  TestTIdSipOutboundUnregister = class(TestTIdSipOutboundRegistration)
  private
    Bindings: TIdSipContacts;
    WildCard: Boolean;
  protected
    function CreateAction: TIdSipAction; override;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestUnregisterAll;
    procedure TestUnregisterSeveralContacts;
  end;

  TestRegistrationMethod = class(TActionMethodTestCase)
  protected
    Bindings: TIdSipContacts;
    Reg:      TIdSipOutboundRegistration;
    Listener: TIdSipTestRegistrationListener;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  end;

  TestTIdSipRegistrationFailedMethod = class(TestRegistrationMethod)
  private
    Method: TIdSipRegistrationFailedMethod;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRun;
  end;

  TestTIdSipRegistrationSucceededMethod = class(TestRegistrationMethod)
  private
    Method: TIdSipRegistrationSucceededMethod;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRun;
  end;

implementation

uses
  Classes, DateUtils, IdSipConsts, IdTimerQueue, SysUtils;

function Suite: ITestSuite;
begin
  Result := TTestSuite.Create('IdSipRegistrar unit tests');
  Result.AddTest(TestTIdSipRegistrar.Suite);
  Result.AddTest(TestTIdSipOutboundRegisterModule.Suite);
  Result.AddTest(TestTIdSipInboundRegistration.Suite);
  Result.AddTest(TestTIdSipOutboundRegister.Suite);
  Result.AddTest(TestTIdSipOutboundRegistrationQuery.Suite);
  Result.AddTest(TestTIdSipOutboundUnregister.Suite);
  Result.AddTest(TestTIdSipRegistrationFailedMethod.Suite);
  Result.AddTest(TestTIdSipRegistrationSucceededMethod.Suite);
end;

//******************************************************************************
//* TestTIdSipRegistrar                                                        *
//******************************************************************************
//* TestTIdSipRegistrar Public methods *****************************************

procedure TestTIdSipRegistrar.SetUp;
begin
  inherited SetUp;

  Self.ExpireAll := ContactWildCard + ';' + ExpiresParam + '=0';

  Self.DB := TIdSipMockBindingDatabase.Create;
  Self.DB.FailIsValid := false;
//  Self.DB.DefaultExpiryTime := 0;

  Self.Dispatch := TIdSipMockTransactionDispatcher.Create;
  Self.Registrar := TIdSipRegistrar.Create;
  Self.Registrar.BindingDB := Self.DB;
  Self.Registrar.Dispatcher := Self.Dispatch;
  Self.Registrar.MinimumExpiryTime := 3600;

  Self.Request := TIdSipRequest.Create;
  Self.Request.Method := MethodRegister;
  Self.Request.RequestUri.Uri := 'sip:tessier-ashpool.co.luna';
  Self.Request.AddHeader(ViaHeaderFull).Value := 'SIP/2.0/TCP proxy.tessier-ashpool.co.luna;branch='
                                               + BranchMagicCookie + 'f00L';
  Self.Request.ToHeader.Address.Uri := 'sip:wintermute@tessier-ashpool.co.luna';
  Self.Request.AddHeader(ContactHeaderFull).Value := 'sip:wintermute@talking-head.tessier-ashpool.co.luna';
  Self.Request.CSeq.Method := Self.Request.Method;
  Self.Request.CallID := '1@selftest.foo';
  Self.Request.From.Address.Uri := 'sip:case@fried.neurons.org';

  Self.FirstContact := Self.Request.FirstHeader(ContactHeaderFull) as TIdSipContactHeader;

  // No A/AAAA records mean no possible locations!
  Self.Dispatch.MockLocator.AddA(Self.Request.LastHop.SentBy, '127.0.0.1');
end;

procedure TestTIdSipRegistrar.TearDown;
begin
  Self.Request.Free;
  Self.Registrar.Free;
  Self.Dispatch.Free;
  Self.DB.Free;

  inherited TearDown;
end;

//* TestTIdSipRegistrar Private methods ****************************************

procedure TestTIdSipRegistrar.CheckResponse(Received: TIdSipContacts;
                                            const Msg: String);
var
  Expected: TIdSipContacts;
  I:        Integer;
begin
  Expected := TIdSipContacts.Create(Self.Dispatch.Transport.LastResponse.Headers);
  try
    Expected.First;
    Received.First;

    I := 0;
    while Expected.HasNext do begin
      Check(Received.HasNext, 'Received too few Expected');

      Check(Abs(Expected.CurrentContact.Expires
              - Received.CurrentContact.Expires) < 2,
            'Expires param; I = ' + IntToStr(I));

      Expected.CurrentContact.RemoveExpires;
      Received.CurrentContact.RemoveExpires;
      CheckEquals(Expected.CurrentContact.Address.Uri,
                  Received.CurrentContact.Address.Uri,
            'URI; I = ' + IntToStr(I));

      Expected.Next;
      Received.Next;
      Inc(I);
    end;
  finally
    Expected.Free;
  end;
end;

procedure TestTIdSipRegistrar.CheckServerReturned(ExpectedStatusCode: Cardinal;
                                                  const Msg: String);
begin
  Check(Self.Dispatch.Transport.SentResponseCount > 0,
        Msg + ': No responses ever sent');
  CheckEquals(ExpectedStatusCode,
              Self.Dispatch.Transport.LastResponse.StatusCode,
              Msg
            + ': Status code of last response ('
            + Self.Dispatch.Transport.LastResponse.StatusText
            + ')');
end;

procedure TestTIdSipRegistrar.CheckServerReturnedOK(const Msg: String);
begin
  Self.CheckServerReturned(SIPOK, Msg);
end;

procedure TestTIdSipRegistrar.SimulateRemoteRequest;
begin
  Self.Dispatch.Transport.FireOnRequest(Self.Request);
end;

//* TestTIdSipRegistrar Published methods **************************************

procedure TestTIdSipRegistrar.TestComplicatedRegistration;
var
  Bindings:   TIdSipContacts;
  OldContact: String;
  NewContact: String;
begin
  // This plays with a mis-ordered request.
  // We register 'sip:wintermute@talking-head.tessier-ashpool.co.luna' with CSeq 999
  // We register 'sip:wintermute@talking-head-2.tessier-ashpool.co.luna' with CSeq 1001
  // We try to remove all registrations with CSeq 1000
  // We expect to see only the talking-head-2. (The remove-all is out of
  // order only with respect to the talking-head-2 URI.

  OldContact := 'sip:wintermute@talking-head.tessier-ashpool.co.luna';
  NewContact := 'sip:wintermute@talking-head-2.tessier-ashpool.co.luna';

  Self.Request.FirstContact.Value := OldContact;
  Self.Request.CSeq.SequenceNo    := 999;
  Self.SimulateRemoteRequest;
  Self.CheckServerReturnedOK('Step 1: registering <' + OldContact + '>');

  Self.Request.FirstContact.Value := NewContact;
  Self.Request.CSeq.SequenceNo    := 1001;
  Self.Request.LastHop.Branch     := Self.Request.LastHop.Branch + '1';
  Self.SimulateRemoteRequest;
  Self.CheckServerReturnedOK('Step 2: registering <' + NewContact + '>');

  Self.Request.FirstContact.IsWildCard := true;
  Self.Request.FirstContact.Expires    := 0;
  Self.Request.CSeq.SequenceNo         := 1000;
  Self.Request.LastHop.Branch          := Self.Request.LastHop.Branch + '1';
  Self.SimulateRemoteRequest;
  Self.CheckServerReturnedOK('Step 3: unregistering everything, out-of-order');

  Bindings := TIdSipContacts.Create;
  try
    Self.DB.BindingsFor(Self.Request, Bindings);
    Bindings.First;
    Check(not Bindings.IsEmpty, 'All bindings were removed');
    Bindings.CurrentContact.RemoveExpires;
    CheckEquals(NewContact,
                Bindings.CurrentContact.Address.Uri,
                'Wrong binding removed');
  finally
    Bindings.Free;
  end;
end;

procedure TestTIdSipRegistrar.TestDatabaseUpdatesBindings;
var
  Contacts: TIdSipContacts;
begin
  Self.Request.FirstContact.Expires := Self.Registrar.MinimumExpiryTime + 1;
  Self.SimulateRemoteRequest;
  Self.CheckServerReturnedOK('First registration');
  Self.Request.FirstContact.Expires := Self.Registrar.MinimumExpiryTime + 100;
  Self.Request.CSeq.Increment;
  Self.SimulateRemoteRequest;
  Self.CheckServerReturnedOK('Second registration');

  Contacts := TIdSipContacts.Create;
  try
    Self.Registrar.BindingDB.BindingsFor(Self.Request, Contacts);
    Check(not Contacts.IsEmpty, 'No contacts? Binding deleted?');
    Contacts.First;
    CheckEquals(Self.Request.FirstContact.Address.Uri,
                Contacts.CurrentContact.Address.Uri,
                'Binding DB not updated');
  finally
    Contacts.Free;
  end;
end;

procedure TestTIdSipRegistrar.TestDatabaseGetsExpiry;
var
  Expiry: TDateTime;
begin
  Self.FirstContact.Expires := Self.Registrar.MinimumExpiryTime + 1;
  Expiry := Now + OneSecond*Self.FirstContact.Expires;
  Self.SimulateRemoteRequest;
  Self.CheckServerReturnedOK('Attempted registration');

  CheckEquals(1, Self.DB.BindingCount, 'Binding not added');

  // Of course, we're comparing two floats. The tolerance should be sufficient
  // to take into account heavy CPU loads. Besides, what's 200ms between
  // friends?
  CheckEquals(Expiry,
              Self.DB.BindingExpires(Self.Request.AddressOfRecord,
                                     Self.FirstContact.AsAddressOfRecord),
              200*OneMillisecond,
              'Binding won''t expire at right time');
end;

procedure TestTIdSipRegistrar.TestFailedBindingsFor;
begin
  Self.DB.FailBindingsFor := true;
  Self.SimulateRemoteRequest;
  Self.CheckServerReturned(SIPInternalServerError,
                           'BindingsFor failed');
end;

procedure TestTIdSipRegistrar.TestFailedRemoveAll;
begin
  Self.SimulateRemoteRequest;
  Self.CheckServerReturnedOK('Registration');

  // We must change the branch or the UAS will think we want to send the
  // request to the old REGISTER transaction, which we don't. That
  // transaction's still alive because its Timer J hasn't fired - that's
  // usually a 32 second wait.
  Self.Request.LastHop.Branch := Self.Request.LastHop.Branch + '1';
  Self.Request.CSeq.Increment;
  Self.Request.FirstContact.Value := '*;expires=0';
  Self.DB.FailRemoveBinding := true;

  Self.SimulateRemoteRequest;
  Self.CheckServerReturned(SIPInternalServerError,
                           'Binding database failed during removal of bindings');
end;

procedure TestTIdSipRegistrar.TestInvalidAddressOfRecord;
begin
  Self.DB.FailIsValid := true;
  Self.SimulateRemoteRequest;
  Self.CheckServerReturned(SIPNotFound,
                           'Invalid address-of-record');
end;

procedure TestTIdSipRegistrar.TestMethod;
begin
  CheckEquals(MethodRegister,
              TIdSipInboundRegistration.Method,
              'Inbound registration; Method');
end;

procedure TestTIdSipRegistrar.TestOKResponseContainsAllBindings;
var
  Bindings: TIdSipContacts;
begin
  Self.Request.AddHeader(ContactHeaderFull).Value := 'sip:wintermute@talking-head-2.tessier-ashpool.co.luna';
  Self.SimulateRemoteRequest;
  Self.CheckServerReturnedOK('Adding binding');

  Bindings := TIdSipContacts.Create;
  try
    Self.DB.BindingsFor(Self.Request, Bindings);
    CheckResponse(Bindings, 'OK response doesn''t contain all bindings');
  finally
    Bindings.Free;
  end;

  Check(Self.Dispatch.Transport.LastResponse.HasHeader(DateHeader),
        'Registrars SHOULD put a Date header in a 200 OK');
end;

procedure TestTIdSipRegistrar.TestReceiveInvite;
begin
  Self.Request.Method      := MethodInvite;
  Self.Request.CSeq.Method := Self.Request.Method;
  Self.SimulateRemoteRequest;
  
  Self.CheckServerReturned(SIPNotImplemented,
                           'INVITE');
end;

procedure TestTIdSipRegistrar.TestReceiveRegister;
var
  RegistrationCount: Cardinal;
begin
  RegistrationCount := Self.Registrar.RegistrationCount;
  Self.SimulateRemoteRequest;
  CheckEquals(1,
              Self.Dispatch.Transport.SentResponseCount,
              'No response sent');
  CheckNotEquals(SIPMethodNotAllowed,
                 Self.Dispatch.Transport.LastResponse.StatusCode,
                'Registrars MUST accept REGISTER');
  CheckEquals(RegistrationCount,
              Self.Registrar.RegistrationCount,
              'InboundRegistration object not freed');
end;

procedure TestTIdSipRegistrar.TestReceiveExpireTooShort;
var
  Response: TIdSipResponse;
begin
  Self.Request.AddHeader(ExpiresHeader).Value := IntToStr(Self.Registrar.MinimumExpiryTime - 1);
  Self.SimulateRemoteRequest;
  Self.CheckServerReturned(SIPIntervalTooBrief,
                           'Expires header value too low');
  Response := Self.Dispatch.Transport.LastResponse;
  Check(Response.HasHeader(MinExpiresHeader),
        MinExpiresHeader + ' missing');
  CheckEquals(Self.Registrar.MinimumExpiryTime,
              Response.MinExpires.NumericValue,
              MinExpiresHeader + ' value');
end;

procedure TestTIdSipRegistrar.TestReceiveExpireParamTooShort;
var
  Response: TIdSipResponse;
begin
  Self.FirstContact.Expires := Self.Registrar.MinimumExpiryTime - 1;
  Self.SimulateRemoteRequest;
  Self.CheckServerReturned(SIPIntervalTooBrief,
                           'Expires param value too low');

  Response := Self.Dispatch.Transport.LastResponse;
  Check(Response.HasHeader(MinExpiresHeader),
        MinExpiresHeader + ' missing');
  CheckEquals(Self.Registrar.MinimumExpiryTime,
              Response.MinExpires.NumericValue,
              MinExpiresHeader + ' value');
end;

procedure TestTIdSipRegistrar.TestReceiveWildcard;
begin
  Self.DB.AddBindings(Self.Request);
  // Remember the rules of RFC 3261 section 10.3 step 6!
  Self.Request.CallID := Self.Request.CallID + '1';

  Self.FirstContact.Value := Self.ExpireAll;
  Self.SimulateRemoteRequest;

  Self.CheckServerReturnedOK('Wildcard contact');

  CheckEquals(0, Self.DB.BindingCount, 'No bindings removed');
end;

procedure TestTIdSipRegistrar.TestReceiveWildcardWithExtraContacts;
begin
  Self.FirstContact.Value := Self.ExpireAll;
  Self.Request.AddHeader(ContactHeaderFull).Value := 'sip:hiro@enki.org';
  Self.SimulateRemoteRequest;
  Self.CheckServerReturned(SIPBadRequest,
                           'Wildcard contact with another contact');
end;

procedure TestTIdSipRegistrar.TestReceiveWildcardWithNonzeroExpiration;
begin
  Self.FirstContact.Value := Self.ExpireAll;
  Self.FirstContact.Expires := 1;
  Self.SimulateRemoteRequest;
  Self.CheckServerReturned(SIPBadRequest,
                           'Wildcard contact with non-zero expires');
end;

procedure TestTIdSipRegistrar.TestRegisterAddsBindings;
var
  Bindings: TIdSipContacts;
begin
  Self.SimulateRemoteRequest;
  Self.CheckServerReturnedOK('Registration');

  Bindings := TIdSipContacts.Create;
  try
    Self.DB.BindingsFor(Self.Request, Bindings);
    CheckEquals(1, Bindings.Count, 'Binding not added');

    CheckEquals(Self.FirstContact.Address.Uri,
                Bindings.Items[0].Value,
                'First (only) binding');
  finally
    Bindings.Free;
  end;
end;

procedure TestTIdSipRegistrar.TestRegisterAddsMultipleBindings;
var
  Bindings:      TIdSipContacts;
  SecondBinding: String;
begin
  SecondBinding := 'sip:wintermute@talking-head-2.tessier-ashpool.co.luna';
  Self.Request.AddHeader(ContactHeaderFull).Value := SecondBinding;

  Self.SimulateRemoteRequest;
  Self.CheckServerReturnedOK('Registration of multiple bindings');

  Bindings := TIdSipContacts.Create;
  try
    Self.DB.BindingsFor(Self.Request, Bindings);
    CheckEquals(2, Bindings.Count, 'Incorrect number of bindings');

    CheckEquals(Self.FirstContact.Address.Uri,
                Bindings.Items[0].Value,
                'First binding');
    CheckEquals(SecondBinding,
                Bindings.Items[1].Value,
                'Second binding');
  finally
    Bindings.Free;
  end;
end;

procedure TestTIdSipRegistrar.TestRejectRegisterWithReplacesHeader;
begin
  Self.Request.AddHeader(ReplacesHeader).Value := '1;from-tag=2;to-tag=3';
  Self.SimulateRemoteRequest;
  Self.CheckServerReturned(SIPBadRequest,
                           'Replaces header in a REGISTER');
end;

procedure TestTIdSipRegistrar.TestUnauthorizedUser;
begin
  Self.DB.Authorized := false;
  Self.SimulateRemoteRequest;
  Self.CheckServerReturned(SIPForbidden,
                           'Unauthorized user''s request not rejected');
end;

//******************************************************************************
//* TestTIdSipOutboundRegisterModule                                           *
//******************************************************************************
//* TestTIdSipOutboundRegisterModule Public methods ****************************

procedure TestTIdSipOutboundRegisterModule.SetUp;
begin
  inherited SetUp;

  Self.Module    := Self.Core.RegisterModule;
  Self.RemoteUri := TIdSipURI.Create('sip:wintermute@tessier-ashpool.co.luna');

  Self.Locator.AddA(Self.RemoteUri.Host, '127.0.0.1');
end;

procedure TestTIdSipOutboundRegisterModule.TearDown;
begin
  Self.RemoteUri.Free;

  inherited TearDown;
end;

//* TestTIdSipOutboundRegisterModule Published methods *************************

procedure TestTIdSipOutboundRegisterModule.TestCleanUpUnregisters;
begin
  Self.Module.HasRegistrar := true;
  Self.Module.Registrar := Self.Core.From.Address;
  Self.MarkSentRequestCount;

  Self.Module.CleanUp;

  CheckRequestSent('No REGISTER sent');
  CheckEquals(MethodRegister,
              Self.LastSentRequest.Method,
              'Unexpected request sent');
  CheckEquals(0,
              Self.LastSentRequest.QuickestExpiry,
              'Expiry time indicates this wasn''t an un-REGISTER');
end;

procedure TestTIdSipOutboundRegisterModule.TestCreateRegister;
var
  Reg: TIdSipRequest;
begin
  Reg := Self.Module.CreateRegister(Self.Destination);
  try
    CheckEquals(MethodRegister, Reg.Method,              'Incorrect method');
    CheckEquals(MethodRegister, Reg.CSeq.Method,         'Incorrect CSeq method');
    CheckEquals('',             Reg.RequestUri.Username, 'Request-URI Username');
    CheckEquals('',             Reg.RequestUri.Password, 'Request-URI Password');

    CheckEquals(Self.Core.Contact.Value,
                Reg.FirstHeader(ContactHeaderFull).Value,
                'Contact');
    CheckEquals(Self.Core.Contact.Value,
                Reg.ToHeader.Value,
                'To');
    CheckEquals(Reg.ToHeader.Value,
                Reg.From.Value,
                'From');
  finally
    Reg.Free;
  end;
end;

procedure TestTIdSipOutboundRegisterModule.TestCreateRegisterReusesCallIDForSameRegistrar;
var
  FirstCallID:  String;
  Reg:          TIdSipRequest;
  SecondCallID: String;
begin
  Reg := Self.Module.CreateRegister(Self.Destination);
  try
    FirstCallID := Reg.CallID;
  finally
    Reg.Free;
  end;

  Reg := Self.Module.CreateRegister(Self.Destination);
  try
    SecondCallID := Reg.CallID;
  finally
    Reg.Free;
  end;

  CheckEquals(FirstCallID,
              SecondCallID,
              'Call-ID SHOULD be the same for same registrar');

  Self.Destination.Address.Uri := 'sip:enki.org';
  Reg := Self.Module.CreateRegister(Self.Destination);
  try
    CheckNotEquals(FirstCallID,
                   Reg.CallID,
                   'Call-ID SHOULD be different for new registrar');
  finally
    Reg.Free;
  end;
end;

procedure TestTIdSipOutboundRegisterModule.TestReregister;
var
  Event: TIdSipMessageNotifyEventWait;
begin
  Self.Invite.Method := MethodRegister;

  Self.MarkSentRequestCount;

  Event := TIdSipMessageNotifyEventWait.Create;
  try
    Event.Message := Self.Invite.Copy;
    Self.Module.OnReregister(Event);
  finally
    Event.Free;
  end;

  Self.CheckRequestSent('No request resend');
  CheckEquals(MethodRegister,
              Self.LastSentRequest.Method,
              'Unexpected method in resent request');
end;

procedure TestTIdSipOutboundRegisterModule.TestUnregisterFrom;
var
  OurBindings: TIdSipContacts;
begin
  Self.MarkSentRequestCount;
  Self.Module.UnregisterFrom(Self.RemoteUri).Send;
  CheckRequestSent('No REGISTER sent');
  CheckEquals(MethodRegister,
              Self.LastSentRequest.Method,
              'Unexpected sent request');

  OurBindings := TIdSipContacts.Create;
  try
    OurBindings.Add(Self.Core.Contact);

    OurBindings.First;
    Self.LastSentRequest.Contacts.First;

    while (OurBindings.HasNext and Self.LastSentRequest.Contacts.HasNext) do begin
      CheckEquals(OurBindings.CurrentContact.Address.AsString,
                  Self.LastSentRequest.Contacts.CurrentContact.Address.AsString,
                  'Incorrect Contact');

      OurBindings.Next;
      Self.LastSentRequest.Contacts.Next;
    end;
    Check(OurBindings.HasNext = Self.LastSentRequest.Contacts.HasNext,
          'Either not all Contacts in the un-REGISTER, or too many contacts');
  finally
    OurBindings.Free;
  end;
end;

//******************************************************************************
//*  TestTIdSipRegistration                                                    *
//******************************************************************************
//*  TestTIdSipRegistration Public methods *************************************

procedure TestTIdSipRegistration.SetUp;
begin
  inherited SetUp;

  Self.RegisterModule := Self.Core.AddModule(TIdSipRegisterModule) as TIdSipRegisterModule;
  Self.RegisterModule.BindingDB := TIdSipMockBindingDatabase.Create
end;

procedure TestTIdSipRegistration.TearDown;
begin
  Self.RegisterModule.BindingDB.Free;

  inherited TearDown;
end;

//*  TestTIdSipRegistration Published methods **********************************

procedure TestTIdSipRegistration.TestIsRegistration;
var
  Action: TIdSipAction;
begin
  // Self.UA owns the action!
  Action := Self.CreateAction;
  Check(Action.IsRegistration,
        Action.ClassName + ' marked as a Registration');
end;

//******************************************************************************
//*  TestTIdSipInboundRegistration                                             *
//******************************************************************************
//*  TestTIdSipInboundRegistration Public methods ******************************

procedure TestTIdSipInboundRegistration.SetUp;
begin
  inherited SetUp;

  Self.Invite.Method := MethodRegister;
  Self.RegisterAction := TIdSipInboundRegistration.CreateInbound(Self.Core, Self.Invite, false);
end;

procedure TestTIdSipInboundRegistration.TearDown;
begin
  Self.RegisterAction.Free;

  inherited TearDown;
end;

//*  TestTIdSipInboundRegistration Published methods ***************************

procedure TestTIdSipInboundRegistration.TestIsInbound;
begin
  Check(Self.RegisterAction.IsInbound,
        Self.RegisterAction.ClassName + ' not marked as inbound');
end;

procedure TestTIdSipInboundRegistration.TestIsInvite;
begin
  Check(not Self.RegisterAction.IsInvite,
        Self.RegisterAction.ClassName + ' marked as an Invite');
end;

procedure TestTIdSipInboundRegistration.TestIsOptions;
begin
  Check(not Self.RegisterAction.IsOptions,
        Self.RegisterAction.ClassName + ' marked as an Options');
end;

procedure TestTIdSipInboundRegistration.TestIsRegistration;
begin
  Check(Self.RegisterAction.IsRegistration,
        Self.RegisterAction.ClassName + ' not marked as a Registration');
end;

procedure TestTIdSipInboundRegistration.TestIsSession;
begin
  Check(not Self.RegisterAction.IsSession,
        Self.RegisterAction.ClassName + ' marked as a Session');
end;

//******************************************************************************
//*  TestTIdSipOutboundRegistration                                            *
//******************************************************************************
//*  TestTIdSipOutboundRegistration Public methods *****************************

procedure TestTIdSipOutboundRegistration.SetUp;
const
  TwoHours = 7200;
begin
  inherited SetUp;

  Self.Registrar := TIdSipRegistrar.Create;
  Self.Registrar.From.Address.Uri := 'sip:talking-head.tessier-ashpool.co.luna';

  Self.Contacts := TIdSipContacts.Create;
  Self.Contacts.Add(ContactHeaderFull).Value := 'sip:wintermute@talking-head.tessier-ashpool.co.luna';

  Self.Succeeded  := false;
  Self.MinExpires := TwoHours;
end;

procedure TestTIdSipOutboundRegistration.TearDown;
begin
  Self.Contacts.Free;
  Self.Registrar.Free;

  inherited TearDown;
end;

//*  TestTIdSipOutboundRegistration Protected methods **************************

function TestTIdSipOutboundRegistration.RegistrarAddress: TIdSipUri;
begin
  Self.Registrar.From.Address.Uri      := Self.Destination.Address.Uri;
  Self.Registrar.From.Address.Username := '';
  Result := Self.Registrar.From.Address;
end;

//*  TestTIdSipOutboundRegistration Private methods ****************************

procedure TestTIdSipOutboundRegistration.OnFailure(RegisterAgent: TIdSipOutboundRegistration;
                                           CurrentBindings: TIdSipContacts;
                                           Response: TIdSipResponse);
begin
  Self.ActionFailed := true;
end;

procedure TestTIdSipOutboundRegistration.OnSuccess(RegisterAgent: TIdSipOutboundRegistration;
                                           CurrentBindings: TIdSipContacts);
begin
  Self.Succeeded := true;
end;

procedure TestTIdSipOutboundRegistration.ReceiveRemoteIntervalTooBrief;
var
  Response: TIdSipResponse;
begin
  Response := Self.Registrar.CreateResponse(Self.LastSentRequest,
                                            SIPIntervalTooBrief);
  try
    Response.AddHeader(MinExpiresHeader).Value := IntToStr(Self.MinExpires);

    Self.ReceiveResponse(Response);
  finally
    Response.Free;
  end;
end;

//*  TestTIdSipOutboundRegistration Published methods **************************

procedure TestTIdSipOutboundRegistration.TestAddListener;
var
  L1, L2:       TIdSipTestRegistrationListener;
  Registration: TIdSipOutboundRegistration;
begin
  Registration := Self.CreateAction as TIdSipOutboundRegistration;

  L1 := TIdSipTestRegistrationListener.Create;
  try
    L2 := TIdSipTestRegistrationListener.Create;
    try
      Registration.AddListener(L1);
      Registration.AddListener(L2);

      Self.ReceiveOk(Self.LastSentRequest);

      Check(L1.Success, 'L1 not informed of success');
      Check(L2.Success, 'L2 not informed of success');
    finally
      L2.Free;
    end;
  finally
    L1.Free;
  end;
end;

procedure TestTIdSipOutboundRegistration.TestMethod;
begin
  CheckEquals(MethodRegister,
              TIdSipOutboundRegistration.Method,
              'Outbound registration; Method');
end;

procedure TestTIdSipOutboundRegistration.TestReceiveFail;
begin
  Self.CreateAction;
  Self.ReceiveResponse(SIPInternalServerError);
  Check(Self.ActionFailed, 'Registration succeeded');
end;

procedure TestTIdSipOutboundRegistration.TestReceiveIntervalTooBrief;
const
  OneHour = 3600;
begin
  Self.Contacts.First;
  Self.Contacts.CurrentContact.Expires := OneHour;
  Self.CreateAction;

  Self.MarkSentRequestCount;
  Self.ReceiveRemoteIntervalTooBrief;

  CheckRequestSent('No re-request issued');
  Check(Self.LastSentRequest.HasExpiry,
        'Re-request has no expiry');
  CheckEquals(Self.MinExpires,
              Self.LastSentRequest.QuickestExpiry,
              'Re-request minimum expires');

  Self.ReceiveOk(Self.LastSentRequest);
  Check(Self.Succeeded, '(Re-)Registration failed');
end;

procedure TestTIdSipOutboundRegistration.TestReceiveMovedPermanently;
begin
  Self.Locator.AddAAAA('fried.neurons.org', '::1');

  Self.CreateAction;
  Self.MarkSentRequestCount;
  Self.ReceiveMovedPermanently('sip:case@fried.neurons.org');
  CheckRequestSent('No request re-issued for REGISTER');
end;

procedure TestTIdSipOutboundRegistration.TestReceiveOK;
var
  RegistrationCount: Integer;
begin
  Self.CreateAction;

  RegistrationCount := Self.Core.RegisterModule.RegistrationCount;

  Self.ReceiveOk(Self.LastSentRequest);
  Check(Self.Succeeded, 'Registration failed');
  Check(Self.Core.RegisterModule.RegistrationCount < RegistrationCount,
        'REGISTER action not terminated');
end;

procedure TestTIdSipOutboundRegistration.TestRemoveListener;
var
  L1, L2:       TIdSipTestRegistrationListener;
  Registration: TIdSipOutboundRegistration;
begin
  Registration := Self.CreateAction as TIdSipOutboundRegistration;
  L1 := TIdSipTestRegistrationListener.Create;
  try
    L2 := TIdSipTestRegistrationListener.Create;
    try
      Registration.AddListener(L1);
      Registration.AddListener(L2);
      Registration.RemoveListener(L2);

      Self.ReceiveOk(Self.LastSentRequest);

      Check(L1.Success,
            'First listener not notified');
      Check(not L2.Success,
            'Second listener erroneously notified, ergo not removed');
    finally
      L2.Free
    end;
  finally
    L1.Free;
  end;
end;

procedure TestTIdSipOutboundRegistration.TestReregisterTime;
const
  OneMinute     = 60;
  OneHour       = 60*OneMinute;
  OneDay        = 24*OneHour; // Seconds in a day
  FiveMinutes   = 5*OneMinute;
  TwentyMinutes = 20*OneMinute;
var
  Reg: TIdSipOutboundRegistration;
begin
  Reg := Self.CreateAction as TIdSipOutboundRegistration;

  CheckEquals(OneDay - FiveMinutes, Reg.ReregisterTime(OneDay), 'One day');
  CheckEquals(OneHour - FiveMinutes, Reg.ReregisterTime(OneHour), 'One hour');
  CheckEquals(TwentyMinutes - FiveMinutes,
              Reg.ReregisterTime(TwentyMinutes), '20 minutes');

  CheckEquals(FiveMinutes - OneMinute,
              Reg.ReregisterTime(FiveMinutes),
              '5 minutes');

  CheckEquals(4*30 div 5, Reg.ReregisterTime(30), '30 seconds');
  CheckEquals(1,          Reg.ReregisterTime(1), '1 second');
  CheckEquals(1,          Reg.ReregisterTime(0), 'Zero');
end;

procedure TestTIdSipOutboundRegistration.TestSequenceNumberIncrements;
var
  SeqNo: Cardinal;
begin
  Self.CreateAction;
  SeqNo := Self.LastSentRequest.CSeq.SequenceNo;
  Self.CreateAction;
  Check(SeqNo + 1 = Self.LastSentRequest.CSeq.SequenceNo,
        'CSeq sequence number didn''t increment');
end;

procedure TestTIdSipOutboundRegistration.TestUsername;
var
  Registration: TIdSipOutboundRegistration;
begin
  Registration := Self.CreateAction as TIdSipOutboundRegistration;

  Self.Core.From.DisplayName := 'foo';
  CheckEquals(Self.Core.Username,
              Registration.Username,
              'Username "foo"');

  Self.Core.From.DisplayName := 'bar';
  CheckEquals(Self.Core.Username,
              Registration.Username,
              'Username "bar"');
end;

//******************************************************************************
//* TestTIdSipOutboundRegister                                                 *
//******************************************************************************
//* TestTIdSipOutboundRegister Protected methods *******************************

function TestTIdSipOutboundRegister.CreateAction: TIdSipAction;
var
  Reg: TIdSipOutboundRegister;
begin
  Result := Self.Core.RegisterModule.RegisterWith(Self.RegistrarAddress);

  Reg := Result as TIdSipOutboundRegister;
  Reg.AddListener(Self);
  Reg.Bindings  := Self.Contacts;
  Reg.Registrar := Self.RegistrarAddress;
  Result.Send;
end;

//* TestTIdSipOutboundRegister Private methods *********************************

procedure TestTIdSipOutboundRegister.CheckAutoReregister(ReceiveResponse: TExpiryProc;
                                                         EventIsScheduled: Boolean;
                                                         const MsgPrefix: String);
const
  ExpiryTime = 42;
var
  Event:       TNotifyEvent;
  EventCount:  Integer;
  LatestEvent: TIdWait;
begin
  Event := Self.Core.RegisterModule.OnReregister;

  Self.CreateAction;

  EventCount := DebugTimer.EventCount;
  ReceiveResponse(ExpiryTime);

  Self.DebugTimer.LockTimer;
  try
    if EventIsScheduled then begin
      Check(EventCount < Self.DebugTimer.EventCount,
            MsgPrefix + ': No timer added');

      LatestEvent := Self.DebugTimer.FirstEventScheduledFor(@Event);

      Check(Assigned(LatestEvent),
            MsgPrefix + ': Wrong notify event');
      Check(LatestEvent.DebugWaitTime > 0,
            MsgPrefix + ': Bad wait time (' + IntToStr(LatestEvent.DebugWaitTime) + ')');
    end
    else
      CheckEquals(EventCount,
                  Self.DebugTimer.EventCount,
                  MsgPrefix + ': Timer erroneously added');
  finally
    Self.DebugTimer.UnlockTimer;
  end;
end;

procedure TestTIdSipOutboundRegister.ReceiveOkWithContactExpiresOf(ExpiryTime: Cardinal);
var
  Response: TIdSipResponse;
begin
  Response := Self.CreateRemoteOk(Self.LastSentRequest);
  try
    Response.Contacts := Self.LastSentRequest.Contacts;
    Response.FirstContact.Expires := ExpiryTime;

    Response.AddHeader(ContactHeaderFull).Value := Response.FirstContact.AsAddressOfRecord
                                                 + '1;expires=' + IntToStr(ExpiryTime + 1);

    Self.ReceiveResponse(Response);
  finally
    Response.Free;
  end;
end;

procedure TestTIdSipOutboundRegister.ReceiveOkWithExpiresOf(ExpiryTime: Cardinal);
var
  Response: TIdSipResponse;
begin
  Response := Self.CreateRemoteOk(Self.LastSentRequest);
  try
    Response.Contacts := Self.LastSentRequest.Contacts;
    Response.Expires.NumericValue := ExpiryTime;

    Self.ReceiveResponse(Response);
  finally
    Response.Free;
  end;
end;

procedure TestTIdSipOutboundRegister.ReceiveOkWithNoExpires(ExpiryTime: Cardinal);
begin
  Self.ReceiveOk(Self.LastSentRequest);
end;

//* TestTIdSipOutboundRegister Published methods *******************************

procedure TestTIdSipOutboundRegister.TestAutoReregister;
begin
  Self.Core.RegisterModule.AutoReRegister := true;
  Self.CheckAutoReregister(Self.ReceiveOkWithExpiresOf,
                           true,
                           'Expires header');
end;

procedure TestTIdSipOutboundRegister.TestAutoReregisterContactHasExpires;
begin
  Self.Core.RegisterModule.AutoReRegister := true;
  Self.CheckAutoReregister(Self.ReceiveOkWithContactExpiresOf,
                           true,
                           'Contact expires param');
end;

procedure TestTIdSipOutboundRegister.TestAutoReregisterNoExpiresValue;
begin
  Self.Core.RegisterModule.AutoReRegister := true;
  Self.CheckAutoReregister(Self.ReceiveOkWithNoExpires,
                           false,
                           'No Expires header or expires param');
end;

procedure TestTIdSipOutboundRegister.TestAutoReregisterSwitchedOff;
begin
  Self.Core.RegisterModule.AutoReRegister := false;
  Self.CheckAutoReregister(Self.ReceiveOkWithExpiresOf,
                           false,
                           'Expires header; Autoreregister = false');
end;

procedure TestTIdSipOutboundRegister.TestReceiveIntervalTooBriefForOneContact;
const
  OneHour = 3600;
var
  RequestContacts:      TIdSipContacts;
  SecondContactExpires: Cardinal;
begin
  // We try to be tricky: One contact has a (too-brief) expires of one hour.
  // The other has an expires of three hours. The registrar accepts a minimum
  // expires of two hours. We expect the registrar to reject the request with
  // a 423 Interval Too Brief, and for the SipRegistration to re-issue the
  // request leaving the acceptable contact alone and only modifying the
  // too-short contact.

  SecondContactExpires := OneHour*3;

  Self.Contacts.First;
  Self.Contacts.CurrentContact.Expires := OneHour;
  Self.Contacts.Add(ContactHeaderFull).Value := 'sip:wintermute@talking-head-2.tessier-ashpool.co.luna;expires='
                                              + IntToStr(SecondContactExpires);
  Self.CreateAction;

  Self.MarkSentRequestCount;
  Self.ReceiveRemoteIntervalTooBrief;

  CheckRequestSent('No re-request issued');
  Check(Self.LastSentRequest.HasExpiry,
        'Re-request has no expiry');
  CheckEquals(Self.MinExpires,
              Self.LastSentRequest.QuickestExpiry,
              'Re-request minimum expires');
  RequestContacts := TIdSipContacts.Create(Self.LastSentRequest.Headers);
  try
    RequestContacts.First;
    Check(RequestContacts.HasNext,
          'No Contacts');
    Check(RequestContacts.CurrentContact.WillExpire,
          'First contact missing expires');
    CheckEquals(Self.MinExpires,
                RequestContacts.CurrentContact.Expires,
                'First (too brief) contact');
    RequestContacts.Next;
    Check(RequestContacts.HasNext, 'Too few Contacts');
    Check(RequestContacts.CurrentContact.WillExpire,
          'Second contact missing expires');
    CheckEquals(SecondContactExpires,
                RequestContacts.CurrentContact.Expires,
                'Second, acceptable, contact');
  finally
    RequestContacts.Free;
  end;

  Self.ReceiveOk(Self.LastSentRequest);
  Check(Self.Succeeded, '(Re-)Registration failed');
end;

procedure TestTIdSipOutboundRegister.TestRegister;
var
  Request: TIdSipRequest;
begin
  Self.MarkSentRequestCount;
  Self.CreateAction;
  CheckRequestSent('No request sent');

  Request := Self.LastSentRequest;
  CheckEquals(Self.RegistrarAddress.Uri,
              Request.RequestUri.Uri,
              'Request-URI');
  CheckEquals(MethodRegister, Request.Method, 'Method');
  Check(Request.Contacts.Equals(Self.Contacts),
        'Bindings');
end;

//******************************************************************************
//* TestTIdSipOutboundRegistrationQuery                                        *
//******************************************************************************
//* TestTIdSipOutboundRegistrationQuery Protected methods **********************

function TestTIdSipOutboundRegistrationQuery.CreateAction: TIdSipAction;
var
  Reg: TIdSipOutboundRegistrationQuery;
begin
  Result := Self.Core.RegisterModule.CurrentRegistrationWith(Self.RegistrarAddress);

  Reg := Result as TIdSipOutboundRegistrationQuery;
  Reg.AddListener(Self);
  Reg.Registrar := Self.RegistrarAddress;
  Result.Send;
end;

//* TestTIdSipOutboundRegistrationQuery Published methods **********************

procedure TestTIdSipOutboundRegistrationQuery.TestFindCurrentBindings;
var
  Request: TIdSipRequest;
begin
  Self.MarkSentRequestCount;
  Self.CreateAction;
  CheckRequestSent('No request sent');

  Request := Self.LastSentRequest;
  Check(Request.Contacts.IsEmpty,
        'Contact headers present');
end;

//******************************************************************************
//* TestTIdSipOutboundUnregister                                               *
//******************************************************************************
//* TestTIdSipOutboundUnregister Public methods ********************************

procedure TestTIdSipOutboundUnregister.SetUp;
begin
  inherited SetUp;

  Self.Bindings := TIdSipContacts.Create;
  Self.WildCard := false;
end;

procedure TestTIdSipOutboundUnregister.TearDown;
begin
  Self.Bindings.Free;

  inherited TearDown;
end;

//* TestTIdSipOutboundUnregister Protected methods *****************************

function TestTIdSipOutboundUnregister.CreateAction: TIdSipAction;
var
  Reg: TIdSipOutboundUnregister;
begin
  Result := Self.Core.RegisterModule.UnregisterFrom(Self.RegistrarAddress);

  Reg := Result as TIdSipOutboundUnregister;
  Reg.Bindings   := Self.Bindings;
  Reg.IsWildCard := Self.WildCard;
  Reg.AddListener(Self);
  Result.Send;
end;

//* TestTIdSipOutboundUnregister Published methods *****************************

procedure TestTIdSipOutboundUnregister.TestUnregisterAll;
var
  Request: TIdSipRequest;
begin
  Self.MarkSentRequestCount;
  Self.WildCard := true;
  Self.CreateAction;
  CheckRequestSent('No request sent');

  Request := Self.LastSentRequest;
  CheckEquals(Self.RegistrarAddress.Uri,
              Request.RequestUri.Uri,
              'Request-URI');
  CheckEquals(MethodRegister, Request.Method, 'Method');
  CheckEquals(1, Request.Contacts.Count,
             'Contact count');
  Check(Request.FirstContact.IsWildCard,
        'First Contact');
  CheckEquals(0, Request.QuickestExpiry,
             'Request expiry');
end;

procedure TestTIdSipOutboundUnregister.TestUnregisterSeveralContacts;
var
  Request: TIdSipRequest;
begin
  Self.MarkSentRequestCount;
  Self.Bindings.Add(ContactHeaderFull).Value := 'sip:case@fried.neurons.org';
  Self.Bindings.Add(ContactHeaderFull).Value := 'sip:wintermute@tessier-ashpool.co.luna';

  Self.CreateAction;
  CheckRequestSent('No request sent');

  Request := Self.LastSentRequest;
  CheckEquals(Self.RegistrarAddress.Uri,
              Request.RequestUri.Uri,
              'Request-URI');
  CheckEquals(MethodRegister, Request.Method, 'Method');

  Request.Contacts.First;
  Self.Bindings.First;

  while Request.Contacts.HasNext do begin
    CheckEquals(Self.Bindings.CurrentContact.Value,
                Request.Contacts.CurrentContact.Value,
                'Different Contact');

    CheckEquals(0,
                Request.Contacts.CurrentContact.Expires,
                'Expiry of ' + Request.Contacts.CurrentContact.Value);
    Request.Contacts.Next;
    Self.Bindings.Next;
  end;

  CheckEquals(Self.Bindings.Count, Request.Contacts.Count,
             'Contact count');
end;

//******************************************************************************
//* TestRegistrationMethod                                                     *
//******************************************************************************
//* TestRegistrationMethod Public methods **************************************

procedure TestRegistrationMethod.SetUp;
var
  Registrar: TIdSipUri;
begin
  inherited SetUp;

  Registrar := TIdSipUri.Create;
  try
    Reg := Self.UA.RegisterModule.RegisterWith(Registrar);
  finally
    Registrar.Free;
  end;

  Self.Bindings := TIdSipContacts.Create;
  Self.Listener := TIdSipTestRegistrationListener.Create;
end;

procedure TestRegistrationMethod.TearDown;
begin
  Self.Listener.Free;
  Self.Bindings.Free;

  inherited TearDown;
end;

//******************************************************************************
//* TestTIdSipRegistrationFailedMethod                                         *
//******************************************************************************
//* TestTIdSipRegistrationFailedMethod Public methods **************************

procedure TestTIdSipRegistrationFailedMethod.SetUp;
begin
  inherited SetUp;

  Self.Method := TIdSipRegistrationFailedMethod.Create;
  Self.Method.CurrentBindings := Self.Bindings;
  Self.Method.Response        := Self.Response;
  Self.Method.Registration    := Self.Reg;
end;

procedure TestTIdSipRegistrationFailedMethod.TearDown;
begin
  Self.Method.Free;

  inherited TearDown;
end;

//* TestTIdSipRegistrationFailedMethod Published methods ***********************

procedure TestTIdSipRegistrationFailedMethod.TestRun;
begin
  Self.Method.Run(Self.Listener);

  Check(Self.Listener.Failure, 'Listener not notified');
  Check(Self.Method.CurrentBindings = Self.Listener.CurrentBindingsParam,
        'CurrentBindings param');
  Check(Self.Method.Registration = Self.Listener.RegisterAgentParam,
        'RegisterAgent param');
  Check(Self.Method.Response = Self.Listener.ResponseParam,
        'Response param');
end;

//******************************************************************************
//* TestTIdSipRegistrationSucceededMethod                                      *
//******************************************************************************
//* TestTIdSipRegistrationSucceededMethod Public methods ***********************

procedure TestTIdSipRegistrationSucceededMethod.SetUp;
begin
  inherited SetUp;

  Self.Method := TIdSipRegistrationSucceededMethod.Create;
  Self.Method.CurrentBindings := Self.Bindings;
  Self.Method.Registration    := Self.Reg;
end;

procedure TestTIdSipRegistrationSucceededMethod.TearDown;
begin
  Self.Method.Free;

  inherited TearDown;
end;

//* TestTIdSipRegistrationSucceededMethod Published methods ********************

procedure TestTIdSipRegistrationSucceededMethod.TestRun;
begin
  Self.Method.Run(Self.Listener);

  Check(Self.Listener.Success, 'Listener not notified');
  Check(Self.Method.CurrentBindings = Self.Listener.CurrentBindingsParam,
        'CurrentBindings param');
  Check(Self.Method.Registration = Self.Listener.RegisterAgentParam,
        'RegisterAgent param');
end;

initialization
  RegisterTest('Registrar', Suite);
end.
