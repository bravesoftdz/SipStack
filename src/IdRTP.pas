unit IdRTP;

interface

uses
  Classes, Contnrs, IdRTPTimerQueue, IdSocketHandle, IdUDPServer, SyncObjs,
  SysUtils, Types;

type
  TIdCardinalArray        = array of Cardinal;
  TIdTelephoneEventVolume = 0..63;
  TIdNTPTimestamp         = record
    IntegerPart:    Cardinal;
    FractionalPart: Cardinal;
  end;
  TIdLoss                 = 0..16777215; // 3-byte integer: 2^24 - 1
  TIdFiveBitInt           = 0..31;
  TIdRTCPSourceCount      = TIdFiveBitInt;
  TIdRTCPSubType          = TIdFiveBitInt;
  TIdRTCPReceptionCount   = TIdFiveBitInt;
  TIdRTPCsrcCount         = 0..15;
  TIdRTPPayloadType       = Byte;
  TIdRTPSequenceNo        = Word;
  TIdRTPTimestamp         = Cardinal;
  TIdRTPVersion           = 0..3;
  TIdT140BlockCount       = Word;

  TIdRTPPayload = class;
  TIdRTPPayloadClass = class of TIdRTPPayload;

  // I am an Encoding. I am described in an SDP payload (RFC 2327),
  // and instantiated by things that need to describe these sorts
  // of encodings. I am a Value Object.
  TIdRTPEncoding = class(TObject)
  private
    fClockRate:  Cardinal;
    fName:       String;
    fParameters: String;
  protected
    function GetName: String; virtual;
  public
    class function CreateEncoding(Value: String): TIdRTPEncoding;
    class function NullEncoding: TIdRTPEncoding;

    constructor Create(Name: String;
                       ClockRate: Cardinal;
                       Parameters: String = ''); overload; virtual;
    constructor Create(Src: TIdRTPEncoding); overload; virtual;

    function AsString: String; virtual;
    function Clone: TIdRTPEncoding; virtual;
    function CreatePayload: TIdRTPPayload; virtual;
    function IsEqualTo(const OtherEncoding: TIdRTPEncoding): Boolean;
    function IsNull: Boolean; virtual;
    function IsReserved: Boolean; virtual;
    function PayloadType: TIdRTPPayloadClass; virtual;

    property ClockRate:  Cardinal read fClockRate;
    property Name:       String   read GetName;
    property Parameters: String   read fParameters;
  end;

  TIdRTPEncodingClass = class of TIdRTPEncoding;

  TIdT140Encoding = class(TIdRTPEncoding)
  public
    function PayloadType: TIdRTPPayloadClass; override;
  end;

  TIdTelephoneEventEncoding = class(TIdRTPEncoding)
  public
    function PayloadType: TIdRTPPayloadClass; override;
  end;

  // I represent the Null Encoding.
  TIdRTPNullEncoding = class(TIdRTPEncoding)
  public
    constructor Create(Name: String;
                       ClockRate: Cardinal;
                       Parameters: String = ''); overload; override;
    constructor Create(Src: TIdRTPEncoding); overload; override;

    function AsString: String; override;
    function Clone: TIdRTPEncoding; override;
    function CreatePayload: TIdRTPPayload; override;
    function IsNull: Boolean; override;
  end;

  // I am a Reserved or Unassigned encoding in an RTP profile. In other words, I
  // do nothing other than say to you "you may not use this payload type".
  TIdRTPReservedEncoding = class(TIdRTPEncoding)
  public
    constructor Create(Name: String;
                       ClockRate: Cardinal;
                       Parameters: String = ''); overload; override;
    constructor Create(Src: TIdRTPEncoding); overload; override;

    function AsString: String; override;
    function Clone: TIdRTPEncoding; override;
    function IsReserved: Boolean; override;
  end;

  // I represent the payload in an RTP packet. I store a reference to an
  // encoding. I strongly suggest that you don't mix-and-match payloads and
  // encodings. An RFC 2833 payload must work with an RFC 2833 encoding, for
  // instance.
  //
  // I offer a Flyweight Null Payload.
  TIdRTPPayload = class(TPersistent)
  private
    fEncoding:   TIdRTPEncoding;
    fClockRate:  Cardinal;
    fName:       String;
    fParameters: String;
    fStartTime:  TDateTime;
  protected
    function  GetName: String; virtual; abstract;
    function  GetStartTime: TDateTime; virtual;
    procedure SetStartTime(const Value: TDateTime); virtual;
  public
    class function CreateFrom(Encoding: TIdRTPEncoding;
                              Src: TStream): TIdRTPPayload;
    class function NullPayload: TIdRTPPayload;

    constructor Create(Encoding: TIdRTPEncoding);

    procedure Assign(Src: TPersistent); override;
    function  HasKnownLength: Boolean; virtual;
    function  IsNull: Boolean; virtual;
    function  Length: Cardinal; virtual;
    function  NumberOfSamples: Cardinal; virtual;
    procedure ReadFrom(Src: TStream); virtual;
    procedure PrintOn(Dest: TStream); virtual;

    property Encoding:   TIdRTPEncoding read fEncoding;
    property ClockRate:  Cardinal       read fClockRate write fClockRate;
    property Name:       String         read GetName;
    property Parameters: String         read fParameters write fParameters;
    property StartTime:  TDateTime      read GetStartTime write SetStartTime;
  end;

  // I represent the Null payload - a Null Object representing the absence of a
  // payload.
  TIdNullPayload = class(TIdRTPPayload)
  protected
    function  GetStartTime: TDateTime; override;
    procedure SetStartTime(const Value: TDateTime); override;
  public
    function IsNull: Boolean; override;
  end;

  // I represent a raw (i.e., unparsed) payload.
  // I typically provide a fallback case for a malconfigured RTP server.
  TIdRawPayload = class(TIdRTPPayload)
  private
    fData: String;
  public
    function  Length: Cardinal; override;
    procedure ReadFrom(Src: TStream); override;
    procedure PrintOn(Dest: TStream); override;

    property Data: String read fData write fData;
  end;

  // I am a T.140 payload, as defined in RFC 2793 (and the bis draft)
  TIdT140Payload = class(TIdRTPPayload)
  private
    fBlock: String;
  protected
    function GetName: String; override;
  public
    function  HasKnownLength: Boolean; override;
    function  Length: Cardinal; override;
    procedure ReadFrom(Src: TStream); override;
    procedure PrintOn(Dest: TStream); override;

    property Block: String read fBlock write fBlock;
  end;

  // I represent DTMF signals and such, as defined in RFC 2833
  TIdTelephoneEventPayload = class(TIdRTPPayload)
  private
    fDuration:    Word;
    fEvent:       Byte;
    fIsEnd:       Boolean;
    fReservedBit: Boolean;
    fVolume:      TIdTelephoneEventVolume;
  protected
    function GetName: String; override;
  public
    function  NumberOfSamples: Cardinal; override;
    procedure ReadFrom(Src: TStream); override;
    procedure PrintOn(Dest: TStream); override;

    property Duration:    Word                    read fDuration write fDuration;
    property Event:       Byte                    read fEvent write fEvent;
    property IsEnd:       Boolean                 read fIsEnd write fIsEnd;
    property ReservedBit: Boolean                 read fReservedBit write fReservedBit;
    property Volume:      TIdTelephoneEventVolume read fVolume write fVolume;
  end;

  TIdPayloadArray = array[Low(TIdRTPPayloadType)..High(TIdRTPPayloadType)] of TIdRTPEncoding;

  TIdRTPBasePacket = class;

  // I represent a 1-1 association map between encodings and RTP Payload Types.
  // RTP packets use me to determine how their payload should be interpreted.
  // Because I represent a  1-1 relation, you cannot add the same encoding to
  // me twice. If you try, the payload type you try to overwrite will remain
  // unchanged.
  TIdRTPProfile = class(TPersistent)
  private
    Encodings:        TIdPayloadArray;
    NullEncoding:     TIdRTPEncoding;
    ReservedEncoding: TIdRTPEncoding;

    function  IndexOfEncoding(const Encoding: TIdRTPEncoding): Integer;
    procedure Initialize;
    procedure RemoveEncoding(const PayloadType: TIdRTPPayloadType);
  protected
    procedure AddEncodingAsReference(Encoding: TIdRTPEncoding;
                                     PayloadType: TIdRTPPayloadType);

    procedure ReservePayloadType(const PayloadType: TIdRTPPayloadType);
  public
    constructor Create; virtual;
    destructor  Destroy; override;

    procedure AddEncoding(Encoding: TIdRTPEncoding;
                          PayloadType: TIdRTPPayloadType); overload;
    procedure AddEncoding(Name: String;
                          ClockRate: Cardinal;
                          Params: String;
                          PayloadType: TIdRTPPayloadType); overload;
    function  AllowsHeaderExtensions: Boolean; virtual;
    procedure Assign(Src: TPersistent); override;
    procedure Clear;
    function  Count: Integer;
    function  CreatePacket(Src: TStream): TIdRTPBasePacket;
    function  EncodingFor(PayloadType: TIdRTPPayloadType): TIdRTPEncoding; overload;
    function  EncodingFor(EncodingName: String): TIdRTPEncoding; overload;
    function  FirstFreePayloadType: TIdRTPPayloadType;
    function  HasEncoding(const Encoding: TIdRTPEncoding): Boolean;
    function  HasPayloadType(PayloadType: TIdRTPPayloadType): Boolean;
    function  IsFull: Boolean;
    function  IsRTCPPayloadType(const PayloadType: Byte): Boolean;
    function  PayloadTypeFor(Encoding: TIdRTPEncoding): TIdRTPPayloadType;
    function  StreamContainsEncoding(Src: TStream): TIdRTPEncoding;
    function  StreamContainsPayloadType(Src: TStream): TIdRTPPayloadType;
    function  TransportDesc: String; virtual;
  end;

  // I represent the profile defined in RFC 3551. As such, don't bother trying
  // to change the encodings of any reserved or assigned payload types. I only
  // allow the alteration of the dynamic payload types - 96-127.
  TIdAudioVisualProfile = class(TIdRTPProfile)
  private
    procedure ReserveRange(LowPT, HighPT: TIdRTPPayloadType);
  public
    constructor Create; override;

    procedure Assign(Src: TPersistent); override;
    function  TransportDesc: String; override;
  end;

  // I represent a Header Extension. RFC 3550 doesn't define an interpretation
  // for my data beyond the length field, so my subclasses must provide more
  // meaningful properties for this data.
  TIdRTPHeaderExtension = class(TObject)
  private
    fData:                array of Cardinal;
    fProfileDefinedValue: Word;

    function  GetData(Index: Word): Cardinal;
    function  GetLength: Word;
    procedure SetData(Index: Word; const Value: Cardinal);
    procedure SetLength(const Value: Word);
  public
    function  OctetCount: Cardinal;
    procedure ReadFrom(Src: TStream);
    procedure PrintOn(Dest: TStream);

    property Length:              Word     read GetLength write SetLength;
    property ProfileDefinedValue: Word     read fProfileDefinedValue write fProfileDefinedValue;
    property Data[Index: Word]:   Cardinal read GetData write SetData;
  end;

  TIdRTPMember = class;

  TIdRTCPReportBlock = class(TObject)
  private
    fCumulativeLoss:     TIdLoss;
    fDelaySinceLastSR:   Cardinal;
    fFractionLost:       Byte;
    fHighestSeqNo:       Cardinal;
    fInterArrivalJitter: Cardinal;
    fLastSenderReport:   Cardinal;
    fSyncSrcID:          Cardinal;
  public
    procedure GatherStatistics(Member: TIdRTPMember);
    procedure PrintOn(Dest: TStream);
    procedure ReadFrom(Src: TStream);

    property CumulativeLoss:     TIdLoss  read fCumulativeLoss write fCumulativeLoss;
    property DelaySinceLastSR:   Cardinal read fDelaySinceLastSR write fDelaySinceLastSR;
    property FractionLost:       Byte     read fFractionLost write fFractionLost;
    property HighestSeqNo:       Cardinal read fHighestSeqNo write fHighestSeqNo;
    property InterArrivalJitter: Cardinal read fInterArrivalJitter write fInterArrivalJitter;
    property LastSenderReport:   Cardinal read fLastSenderReport write fLastSenderReport;
    property SyncSrcID:          Cardinal read fSyncSrcID write fSyncSrcID;
  end;

  TIdRTPSession = class;

  // Note that my Length property says how many 32-bit words (-1) I contain.
  // IT IS NOT AN OCTET-BASED LENGTH.
  TIdRTPBasePacket = class(TPersistent)
  private
    fHasPadding: Boolean;
    fLength:     Word;
    fSyncSrcID:  Cardinal;
    fVersion:    TIdRTPVersion;
  protected
    function  GetSyncSrcID: Cardinal; virtual;
    procedure PrintPadding(Dest: TStream);
    procedure SetSyncSrcID(const Value: Cardinal); virtual;
  public
    constructor Create;

    procedure Assign(Src: TPersistent); override;
    function  Clone: TIdRTPBasePacket; virtual; abstract;
    function  IsRTCP: Boolean; virtual; abstract;
    function  IsRTP: Boolean; virtual; abstract;
    function  IsValid: Boolean; virtual; abstract;
    procedure PrepareForTransmission(Session: TIdRTPSession); virtual;
    procedure PrintOn(Dest: TStream); virtual; abstract;
    procedure ReadFrom(Src: TStream); virtual; abstract;
    function  RealLength: Word; virtual; abstract;

    property HasPadding: Boolean       read fHasPadding write fHasPadding;
    property Length:     Word          read fLength write fLength;
    property SyncSrcID:  Cardinal      read GetSyncSrcID write SetSyncSrcID;
    property Version:    TIdRTPVersion read fVersion write fVersion;
  end;

  // I represent a packet of the Real-time Transport Protocol.
  // Before you use the CsrcIDs property make sure you set the CsrcCount
  // property!
  TIdRTPPacket = class(TIdRTPBasePacket)
  private
    fCsrcCount:       TIdRTPCsrcCount;
    fCsrcIDs:         TIdCardinalArray;
    fHasExtension:    Boolean;
    fHeaderExtension: TIdRTPHeaderExtension;
    fIsMarker:        Boolean;
    fPayload:         TIdRTPPayload;
    fPayloadType:     TIdRTPPayloadType;
    fSequenceNo:      TIdRTPSequenceNo;
    fTimestamp:       Cardinal;
    Profile:          TIdRTPProfile;

    function  DefaultVersion: TIdRTPVersion;
    function  GetCsrcCount: TIdRTPCsrcCount;
    function  GetCsrcID(Index: TIdRTPCsrcCount): Cardinal;
    procedure ReadPayloadAndPadding(Src: TStream;
                                    Profile: TIdRTPProfile);
    procedure ReplacePayload(const Encoding: TIdRTPEncoding);
    procedure SetCsrcCount(const Value: TIdRTPCsrcCount);
    procedure SetCsrcID(Index: TIdRTPCsrcCount; const Value: Cardinal);
  public
    constructor Create(Profile: TIdRTPProfile);
    destructor  Destroy; override;

    function  Clone: TIdRTPBasePacket; override;
    function  CollidesWith(SSRC: Cardinal): Boolean;
    function  GetAllSrcIDs: TCardinalDynArray;
    function  IsRTCP: Boolean; override;
    function  IsRTP: Boolean; override;
    function  IsValid: Boolean; override;
    procedure PrepareForTransmission(Session: TIdRTPSession); override;
    procedure PrintOn(Dest: TStream); override;
    procedure ReadFrom(Src: TStream); override;
    procedure ReadPayload(Src: TStream; Profile: TIdRTPProfile); overload;
    procedure ReadPayload(Src: String; Profile: TIdRTPProfile); overload;
    procedure ReadPayload(Data: TIdRTPPayload); overload;
    function  RealLength: Word; override;

    property CsrcCount:                       TIdRTPCsrcCount       read GetCsrcCount write SetCsrcCount;
    property CsrcIDs[Index: TIdRTPCsrcCount]: Cardinal              read GetCsrcID write SetCsrcID;
    property HasExtension:                    Boolean               read fHasExtension write fHasExtension;
    property HeaderExtension:                 TIdRTPHeaderExtension read fHeaderExtension;
    property IsMarker:                        Boolean               read fIsMarker write fIsMarker;
    property Payload:                         TIdRTPPayload         read fPayload;
    property PayloadType:                     TIdRTPPayloadType     read fPayloadType write fPayloadType;
    property SequenceNo:                      TIdRTPSequenceNo      read fSequenceNo write fSequenceNo;
    property Timestamp:                       Cardinal              read fTimestamp write fTimestamp;
  end;

  TIdRTCPPacket = class;
  TIdRTCPPacketClass = class of TIdRTCPPacket;

  // I represent a packet in the Real-time Transport Control Protocol, as defined in
  // RFC 3550 section 6.
  TIdRTCPPacket = class(TIdRTPBasePacket)
  protected
    procedure AssertPacketType(const PT: Byte);
    function  GetPacketType: Cardinal; virtual; abstract;
  public
    class function RTCPType(const PacketType: Byte): TIdRTCPPacketClass;

    constructor Create; virtual;

    function Clone: TIdRTPBasePacket; override;
    function IsBye: Boolean; virtual;
    function IsReceiverReport: Boolean; virtual;
    function IsRTCP: Boolean; override;
    function IsRTP: Boolean; override;
    function IsSenderReport: Boolean; virtual;
    function IsSourceDescription: Boolean; virtual;
    function IsValid: Boolean; override;

    property PacketType: Cardinal read GetPacketType;
  end;

  TIdRTCPMultiSSRCPacket = class(TIdRTCPPacket)
  public
    function GetAllSrcIDs: TCardinalDynArray; virtual; abstract;
  end;

  TIdRTCPReceiverReport = class(TIdRTCPMultiSSRCPacket)
  private
    fExtension:        String;
    fReceptionReports: array of TIdRTCPReportBlock;

    procedure ClearReportBlocks;
    function  GetReports(Index: Integer): TIdRTCPReportBlock;
    function  GetReceptionReportCount: TIdRTCPReceptionCount;
    procedure ReInitialiseReportBlocks;
    procedure ReadAllReportBlocks(Src: TStream);
    function  ReportByteLength: Word;
    procedure SetReceptionReportCount(const Value: TIdRTCPReceptionCount);
  protected
    function  FixedHeaderByteLength: Word; virtual;
    function  GetPacketType: Cardinal; override;
    procedure PrintFixedHeadersOn(Dest: TStream); virtual;
    procedure ReadFixedHeadersFrom(Src: TStream); virtual;
  public
    function  GetAllSrcIDs: TCardinalDynArray; override;
    function  IsReceiverReport: Boolean; override;
    procedure PrintOn(Dest: TStream); override;
    procedure ReadFrom(Src: TStream); override;
    function  RealLength: Word; override;

    property Extension:               String                read fExtension write fExtension;
    property ReceptionReportCount:    TIdRTCPReceptionCount read GetReceptionReportCount write SetReceptionReportCount;
    property Reports[Index: Integer]: TIdRTCPReportBlock    read GetReports;
  end;

  // I represent an SR RTCP packet. Please note that I clobber my report
  // objects when you change my ReceptionReportCount property - I free all
  // my existing reports and create new instances. I guarantee that you
  // won't get a nil pointer from ReportAt.
  // Active senders of data in an RTP session send me to give transmission
  // and reception statistics.
  TIdRTCPSenderReport = class(TIdRTCPReceiverReport)
  private
    fNTPTimestamp: TIdNTPTimestamp;
    fOctetCount:   Cardinal;
    fPacketCount:  Cardinal;
    fRTPTimestamp: Cardinal;

  protected
    function  FixedHeaderByteLength: Word; override;
    function  GetPacketType: Cardinal; override;
    procedure PrintFixedHeadersOn(Dest: TStream); override;
    procedure ReadFixedHeadersFrom(Src: TStream); override;
  public
    destructor Destroy; override;

    function  IsReceiverReport: Boolean; override;
    function  IsSenderReport: Boolean; override;
    procedure PrepareForTransmission(Session: TIdRTPSession); override;

    property NTPTimestamp: TIdNTPTimestamp read fNTPTimestamp write fNTPTimestamp;
    property OctetCount:   Cardinal        read fOctetCount write fOctetCount;
    property PacketCount:  Cardinal        read fPacketCount write fPacketCount;
    property RTPTimestamp: Cardinal        read fRTPTimestamp write fRTPTimestamp;
  end;

  TIdSrcDescChunkItem = class;
  TIdSrcDescChunkItemClass = class of TIdSrcDescChunkItem;

  TIdSrcDescChunkItem = class(TObject)
  private
    fData: String;
  protected
    procedure SetData(const Value: String); virtual;
  public
    class function ItemType(ID: Byte): TIdSrcDescChunkItemClass;

    function  ID: Byte; virtual; abstract;
    function  Length: Byte;
    procedure PrintOn(Dest: TStream); virtual;
    procedure ReadFrom(Src: TStream); virtual;
    function  RealLength: Cardinal; virtual;

    property Data: String read fData write SetData;
  end;

  TIdSDESCanonicalName = class(TIdSrcDescChunkItem)
  public
    function ID: Byte; override;
  end;

  TIdSDESUserName = class(TIdSrcDescChunkItem)
  public
    function ID: Byte; override;
  end;

  TIdSDESEmail = class(TIdSrcDescChunkItem)
  public
    function ID: Byte; override;
  end;

  TIdSDESPhone = class(TIdSrcDescChunkItem)
  public
    function ID: Byte; override;
  end;

  TIdSDESLocation = class(TIdSrcDescChunkItem)
  public
    function ID: Byte; override;
  end;

  TIdSDESTool = class(TIdSrcDescChunkItem)
  public
    function ID: Byte; override;
  end;

  TIdSDESNote = class(TIdSrcDescChunkItem)
  public
    function ID: Byte; override;
  end;

  TIdSDESPriv = class(TIdSrcDescChunkItem)
  private
    fPrefix: String;

    function  MaxDataLength: Byte;
    function  MaxPrefixLength: Byte;
    procedure SetPrefix(const Value: String);
    procedure TruncateData;
  protected
    procedure SetData(const Value: String); override;
  public
    function  ID: Byte; override;
    procedure PrintOn(Dest: TStream); override;
    procedure ReadFrom(Src: TStream); override;
    function  RealLength: Cardinal; override;

    property Prefix: String read fPrefix write SetPrefix;
  end;

  TIdRTCPSrcDescChunk = class(TObject)
  private
    fSyncSrcID: Cardinal;
    ItemList:   TObjectList;

    function  AddCanonicalHeader: TIdSDESCanonicalName; overload;
    function  AddItem(ID: Byte): TIdSrcDescChunkItem;
    function  GetItems(Index: Integer): TIdSrcDescChunkItem;
    function  HasMoreItems(Src: TStream): Boolean;
    procedure PrintAlignmentPadding(Dest: TStream);
    procedure ReadAlignmentPadding(Src: TStream);
  public
    constructor Create;
    destructor  Destroy; override;

    procedure AddCanonicalName(Name: String); overload;
    function  ItemCount: Integer;
    procedure PrintOn(Dest: TStream);
    procedure ReadFrom(Src: TStream);
    function  RealLength: Cardinal;

    property Items[Index: Integer]: TIdSrcDescChunkItem read GetItems;
    property SyncSrcID:             Cardinal            read fSyncSrcID write fSyncSrcID;
  end;

  TIdRTCPSourceDescription = class(TIdRTCPMultiSSRCPacket)
  private
    ChunkList: TObjectList;

    function  GetChunks(Index: Integer): TIdRTCPSrcDescChunk;
    procedure ReadChunk(Src: TStream);
  protected
    function  GetPacketType: Cardinal; override;
    function  GetSyncSrcID: Cardinal; override;
    procedure SetSyncSrcID(const Value: Cardinal); override;
  public
    constructor Create; override;
    destructor  Destroy; override;

    function  AddChunk: TIdRTCPSrcDescChunk;
    function  ChunkCount: TIdRTCPSourceCount;
    function  GetAllSrcIDs: TCardinalDynArray; override;
    function  IsSourceDescription: Boolean; override;
    procedure PrintOn(Dest: TStream); override;
    procedure ReadFrom(Src: TStream); override;
    function  RealLength: Word; override;

    property Chunks[Index: Integer]: TIdRTCPSrcDescChunk read GetChunks;
  end;

  // I represent an RTCP Bye packet. You use me to remove yourself from an RTP
  // session. RTP servers that receive me remove the SSRC that sent me from
  // their member tables.
  TIdRTCPBye = class(TIdRTCPMultiSSRCPacket)
  private
    fSources:      TIdCardinalArray;
    fReason:       String;
    fReasonLength: Byte;

    function  GetSourceCount: TIdRTCPSourceCount;
    function  GetSource(Index: TIdRTCPSourceCount): Cardinal;
    procedure ReadReasonPadding(Src: TStream);
    procedure SetReason(const Value: String);
    procedure SetSource(Index: TIdRTCPSourceCount;
                        const Value: Cardinal);
    procedure SetSourceCount(const Value: TIdRTCPSourceCount);
    function  StreamHasReason: Boolean;
  protected
    function  GetPacketType: Cardinal; override;
    function  GetSyncSrcID: Cardinal; override;
    procedure SetSyncSrcID(const Value: Cardinal); override;
  public
    constructor Create; override;

    function  GetAllSrcIDs: TCardinalDynArray; override;
    function  IsBye: Boolean; override;
    procedure PrintOn(Dest: TStream); override;
    procedure ReadFrom(Src: TStream); override;
    function  RealLength: Word; override;

    property Reason:                             String             read fReason write SetReason;
    property ReasonLength:                       Byte               read fReasonLength write fReasonLength;
    property SourceCount:                        TIdRTCPSourceCount read GetSourceCount write SetSourceCount;
    property Sources[Index: TIdRTCPSourceCount]: Cardinal           read GetSource write SetSource;
  end;

  TIdRTCPApplicationDefined = class(TIdRTCPPacket)
  private
    fData:    String;
    fName:    String;
    fSubType: TIdRTCPSubType;

    function  LengthOfName: Byte;
    procedure SetData(const Value: String);
    procedure SetName(const Value: String);
  protected
    function GetPacketType: Cardinal; override;
  public
    constructor Create; override;

    procedure PrintOn(Dest: TStream); override;
    procedure ReadFrom(Src: TStream); override;
    function  RealLength: Word; override;

    property Data:    String         read fData write SetData;
    property Name:    String         read fName write SetName;
    property SubType: TIdRTCPSubType read fSubType write fSubType;
  end;

  TIdCompoundRTCPPacket = class(TIdRTCPPacket)
  private
    Packets: TObjectList;

    function Add(PacketType: TIdRTCPPacketClass): TIdRTCPPacket;
  protected
    function GetPacketType: Cardinal; override;
  public
    constructor Create; override;
    destructor  Destroy; override;

    function  AddApplicationDefined: TIdRTCPApplicationDefined;
    function  AddBye: TIdRTCPBye;
    function  AddReceiverReport: TIdRTCPReceiverReport;
    function  AddSenderReport: TIdRTCPSenderReport;
    function  AddSourceDescription: TIdRTCPSourceDescription;
    function  FirstPacket: TIdRTCPPacket;
    function  HasBye: Boolean;
    function  HasSourceDescription: Boolean;
    function  IsRTCP: Boolean; override;
    function  IsRTP: Boolean; override;
    function  IsValid: Boolean; override;
    function  PacketAt(Index: Cardinal): TIdRTCPPacket;
    function  PacketCount: Cardinal;
    procedure PrepareForTransmission(Session: TIdRTPSession); override;
    procedure PrintOn(Dest: TStream); override;
    procedure ReadFrom(Src: TStream); override;
    function  RealLength: Word; override;
  end;

  // I represent a member in an RTP session.
  // I keep track of Quality of Service statistics and source/control addresses.
  // Too, I provide authentication - a session doesn't regard a packet source as
  // a member until a certain minimum number of packets arrive with sequential
  // sequence numbers (for certain values of "sequential". I store this minimum
  // number in the parameter MinimumSequentialPackets. MaxMisOrder and MaxDropout
  // provide control over what "sequential" means - MaxDropout determines an upper
  // bound on old sequence numbers, and MaxMisOrder an upper bound on sequence
  // number jumps. 
  TIdRTPMember = class(TObject)
  private
    fBadSeqNo:                    Cardinal;
    fBaseSeqNo:                   Word;
    fCanonicalName:               String;
    fControlAddress:              String;
    fControlPort:                 Cardinal;
    fCycles:                      Cardinal; // The (shifted) count of sequence number wraparounds
    fExpectedPrior:               Cardinal;
    fHasLeftSession:              Boolean;
    fHighestSeqNo:                Word;
    fIsSender:                    Boolean;
    fJitter:                      Cardinal;
    fLastRTCPReceiptTime:         TDateTime;
    fLastRTPReceiptTime:          TDateTime;
    fLastSenderReportReceiptTime: TDateTime;
    fLocalAddress:                Boolean;
    fMaxDropout:                  Word;
    fMaxMisOrder:                 Word;
    fMinimumSequentialPackets:    Word;
    fPreviousPacketTransit:       Int64; // Transit time of previous packet in clock rate ticks
    fProbation:                   Cardinal;
    fReceivedPackets:             Cardinal;
    fReceivedPrior:               Cardinal;
    fSentControl:                 Boolean;
    fSentData:                    Boolean;
    fSourceAddress:               String;
    fSourcePort:                  Cardinal;
    fSyncSrcID:                   Cardinal;

    function  DefaultMaxDropout: Cardinal;
    function  DefaultMaxMisOrder: Word;
    function  DefaultMinimumSequentialPackets: Cardinal;
    function  ExpectedPacketCount: Cardinal;
    procedure UpdateJitter(Data: TIdRTPPacket; CurrentTime: Cardinal);
    procedure UpdatePrior;
    function  UpdateSequenceNo(Data: TIdRTPPacket): Boolean;
  public
    constructor Create;

    function  DelaySinceLastSenderReport: Cardinal;
    procedure InitSequence(Data: TIdRTPPacket);
    function  IsInSequence(Data: TIdRTPPacket): Boolean;
    function  IsUnderProbation: Boolean;
    function  LastSenderReport: Cardinal;
    function  PacketLossCount: Cardinal;
    function  PacketLossFraction: Byte;
    function  SequenceNumberRange: Cardinal;
    function  UpdateStatistics(Data:  TIdRTPPacket; CurrentTime: TIdRTPTimestamp): Boolean; overload;
    procedure UpdateStatistics(Stats: TIdRTCPPacket); overload;

    property CanonicalName:               String    read fCanonicalName write fCanonicalName;
    property ControlAddress:              String    read fControlAddress write fControlAddress;
    property ControlPort:                 Cardinal  read fControlPort write fControlPort;
    property HasLeftSession:              Boolean   read fHasLeftSession write fHasLeftSession;
    property IsSender:                    Boolean   read fIsSender write fIsSender;
    property LocalAddress:                Boolean   read fLocalAddress write fLocalAddress;
    property LastRTCPReceiptTime:         TDateTime read fLastRTCPReceiptTime write fLastRTCPReceiptTime;
    property LastRTPReceiptTime:          TDateTime read fLastRTPReceiptTime write fLastRTPReceiptTime;
    property LastSenderReportReceiptTime: TDateTime read fLastSenderReportReceiptTime write fLastSenderReportReceiptTime;
    property SentControl:                 Boolean   read fSentControl write fSentControl;
    property SentData:                    Boolean   read fSentData write fSentData;
    property SourceAddress:               String    read fSourceAddress write fSourceAddress;
    property SourcePort:                  Cardinal  read fSourcePort write fSourcePort;
    property SyncSrcID:                   Cardinal  read fSyncSrcID write fSyncSrcID;

    // Sequence number validity, bytecounts, etc
    property HighestSeqNo:          Word     read fHighestSeqNo write fHighestSeqNo;
    property Cycles:                Cardinal read fCycles write fCycles;
    property BaseSeqNo:             Word     read fBaseSeqNo write fBaseSeqNo;
    property BadSeqNo:              Cardinal read fBadSeqNo write fBadSeqNo;
    property PreviousPacketTransit: Int64    read fPreviousPacketTransit write fPreviousPacketTransit;
    property Probation:             Cardinal read fProbation write fProbation;
    property ReceivedPackets:       Cardinal read fReceivedPackets write fReceivedPackets;
    property ExpectedPrior:         Cardinal read fExpectedPrior write fExpectedPrior;
    property ReceivedPrior:         Cardinal read fReceivedPrior write fReceivedPrior;
    property Jitter:                Cardinal read fJitter write fJitter;

    // Parameters for handling sequence validity
    property MaxDropout:               Word read fMaxDropout write fMaxDropout;
    property MinimumSequentialPackets: Word read fMinimumSequentialPackets write fMinimumSequentialPackets;
    property MaxMisOrder:              Word read fMaxMisOrder write fMaxMisOrder;
  end;

  TIdRTPMemberTable = class(TObject)
  private
    function CompensationFactor: Double;
    function RandomTimeFactor: Double;
  protected
    List: TObjectList;
  public
    constructor Create;
    destructor  Destroy; override;

    function  Add(SSRC: Cardinal): TIdRTPMember;
    function  AddSender(SSRC: Cardinal): TIdRTPMember;
    procedure AdjustTransmissionTime(PreviousMemberCount: Cardinal;
                                     var NextTransmissionTime: TDateTime;
                                     var PreviousTransmissionTime: TDateTime);
    function  Contains(SSRC: Cardinal): Boolean;
    function  Count: Cardinal;
    function  DeterministicSendInterval(ForSender: Boolean;
                                        Session: TIdRTPSession): TDateTime;
    function  Find(SSRC: Cardinal): TIdRTPMember;
    function  MemberAt(Index: Cardinal): TIdRTPMember;
    function  MemberTimeout(Session: TIdRTPSession): TDateTime;
    function  ReceiverCount: Cardinal;
    procedure Remove(SSRC: Cardinal);
    procedure RemoveAll;
    procedure RemoveSources(Bye: TIdRTCPBye);
    procedure RemoveTimedOutMembersExceptFor(CutoffTime: TDateTime;
                                             SessionSSRC: Cardinal);
    procedure RemoveTimedOutSenders(CutoffTime: TDateTime);
    function  SenderCount: Cardinal;
    function  SenderTimeout(Session: TIdRTPSession): TDateTime;
    function  SendInterval(Session: TIdRTPSession): TDateTime;
    procedure SetControlBinding(SSRC: Cardinal;
                                Binding: TIdSocketHandle);
    procedure SetControlBindings(SSRCs: TCardinalDynArray;
                                 Binding: TIdSocketHandle);
    procedure SetDataBinding(SSRC: Cardinal; Binding: TIdSocketHandle);

    property Members[Index: Cardinal]: TIdRTPMember read MemberAt;
  end;

  // I am a filter on a TIdRTPMemberTable. Using me allows you to iterate
  // through all the senders in a member table (i.e., members with IsSender
  // set to true) while ignoring the non-senders.
  TIdRTPSenderTable = class(TObject)
  private
    Members: TIdRTPMemberTable;
  public
    constructor Create(MemberTable: TIdRTPMemberTable);

    function  Add(SSRC: Cardinal): TIdRTPMember;
    function  Contains(SSRC: Cardinal): Boolean;
    function  Count: Cardinal;
    function  Find(SSRC: Cardinal): TIdRTPMember;
    function  MemberAt(Index: Cardinal): TIdRTPMember;
    procedure Remove(SSRC: Cardinal);
    procedure RemoveAll;
  end;

  TIdAbstractRTPPeer = class(TIdUDPServer)
  public
    procedure SendPacket(Host: String;
                         Port: Cardinal;
                         Packet: TIdRTPBasePacket); virtual; abstract;
  end;

  // I provide a self-contained SSRC space.
  // All values involving time represent milliseconds / ticks.
  //
  // current responsibilities:
  // * Keep track of members/senders
  // * Keep track of timing stuff
  // * Keep track of session state
  TIdRTPSession = class(TObject)
  private
    Agent:                      TIdAbstractRTPPeer;
    BaseTime:                   TDateTime;
    BaseTimestamp:              Cardinal; // in clock rate ticks
    fSyncSrcID:                 Cardinal;
    fAssumedMTU:                Cardinal;
    fAvgRTCPSize:               Cardinal;
    fCanonicalName:             String;
    fNoControlSent:             Boolean;
    fMaxRTCPBandwidth:          Cardinal; // octets per second
    fPreviousMemberCount:       Cardinal; // member count at last transmission time
    fReceiverBandwidthFraction: Double;
    fMissedReportTolerance:     Cardinal;
    fSenderBandwidthFraction:   Double;
    fSentOctetCount:            Cardinal;
    fSentPacketCount:           Cardinal;
    fSessionBandwidth:          Cardinal;
    MemberLock:                 TCriticalSection;
    Members:                    TIdRTPMemberTable;
    NextTransmissionTime:       TDateTime;
    NoDataSent:                 Boolean;
    PreviousTransmissionTime:   TDateTime;
    Profile:                    TIdRTPProfile;
    Senders:                    TIdRTPSenderTable;
    SequenceNo:                 TIdRTPSequenceNo;
    Timer:                      TIdRTPTimerQueue;
    TransmissionLock:           TCriticalSection;

    function  AddAppropriateReportTo(Packet: TIdCompoundRTCPPacket): TIdRTCPReceiverReport;
    procedure AddControlSource(ID: Cardinal; Binding: TIdSocketHandle);
    procedure AddControlSources(RTCP: TIdRTCPMultiSSRCPacket;
                                Binding: TIdSocketHandle);
    procedure AddDataSource(ID: Cardinal; Binding: TIdSocketHandle);
    procedure AddReports(Packet: TIdCompoundRTCPPacket);
    procedure AddSourceDesc(Packet: TIdCompoundRTCPPacket);
    procedure AdjustAvgRTCPSize(Control: TIdRTCPPacket);
    procedure AdjustTransmissionTime(Members: TIdRTPMemberTable);
    function  DefaultAssumedMTU: Cardinal;
    function  DefaultMissedReportTolerance: Cardinal;
    function  DefaultNoControlSentAvgRTCPSize: Cardinal;
    function  DefaultReceiverBandwidthFraction: Double;
    function  DefaultSenderBandwidthFraction: Double;
    procedure IncSentOctetCount(N: Cardinal);
    procedure IncSentPacketCount;
    procedure RemoveSources(Bye: TIdRTCPBye);
    procedure ResetSentOctetCount;
    procedure ResetSentPacketCount;
    procedure SendDataToTable(Data: TIdRTPPayload; Table: TIdRTPMemberTable);
    procedure SetSyncSrcId(const Value: Cardinal);
    procedure TransmissionTimeExpire(Sender: TObject);
  public
    constructor Create(Agent: TIdAbstractRTPPeer;
                       Profile: TIdRTPProfile);
    destructor  Destroy; override;

    function  AcceptableSSRC(SSRC: Cardinal): Boolean;
    function  AddMember(SSRC: Cardinal): TIdRTPMember;
    function  AddSender(SSRC: Cardinal): TIdRTPMember;
    function  CreateNextReport: TIdCompoundRTCPPacket;
    function  DeterministicSendInterval(ForSender: Boolean): TDateTime;
    procedure Initialize;
    function  IsMember(SSRC: Cardinal): Boolean;
    function  IsSender: Boolean; overload;
    function  IsSender(SSRC: Cardinal): Boolean; overload;
    procedure LeaveSession(Reason: String = '');
    function  LockMembers: TIdRTPMemberTable;
    function  Member(SSRC: Cardinal): TIdRTPMember;
    function  MemberCount: Cardinal;
    function  MinimumRTCPSendInterval: TDateTime;
    function  NewSSRC: Cardinal;
    function  NextSequenceNo: TIdRTPSequenceNo;
    function  NothingSent: Boolean;
    procedure ReceiveControl(RTCP: TIdRTCPPacket;
                             Binding: TIdSocketHandle);
    procedure ReceiveData(RTP: TIdRTPPacket;
                          Binding: TIdSocketHandle);
    function  ReceiverCount: Cardinal;
    procedure RemoveMember(SSRC: Cardinal);
    procedure RemoveSender(SSRC: Cardinal);
    procedure RemoveTimedOutMembers;
    procedure RemoveTimedOutSenders;
    procedure ResolveSSRCCollision;
    procedure SendControl(Packet: TIdRTCPPacket);
    procedure SendData(Data: TIdRTPPayload);
    procedure SendDataTo(Data: TIdRTPPayload;
                         Host: String;
                         Port: Cardinal);
    function  Sender(SSRC: Cardinal): TIdRTPMember;
    function  SenderAt(Index: Cardinal): TIdRTPMember;
    function  SenderCount: Cardinal;
    procedure SendReport;
    function  TimeOffsetFromStart(WallclockTime: TDateTime): TDateTime;
    procedure UnlockMembers;

    property AssumedMTU:                Cardinal read fAssumedMTU write fAssumedMTU;
    property AvgRTCPSize:               Cardinal read fAvgRTCPSize;
    property CanonicalName:             String   read fCanonicalName write fCanonicalName;
    property NoControlSent:             Boolean  read fNoControlSent;
    property MaxRTCPBandwidth:          Cardinal read fMaxRTCPBandwidth write fMaxRTCPBandwidth;
    property PreviousMemberCount:       Cardinal read fPreviousMemberCount;
    property MissedReportTolerance:     Cardinal read fMissedReportTolerance write fMissedReportTolerance;
    property ReceiverBandwidthFraction: Double   read fReceiverBandwidthFraction write fReceiverBandwidthFraction;
    property SenderBandwidthFraction:   Double   read fSenderBandwidthFraction write fSenderBandwidthFraction;
    property SentOctetCount:            Cardinal read fSentOctetCount;
    property SentPacketCount:           Cardinal read fSentPacketCount;
    property SessionBandwith:           Cardinal read fSessionBandwidth write fSessionBandwidth;
    property SyncSrcID:                 Cardinal read fSyncSrcID;
  end;

  // I provide a buffer to objects that receive RTP packets. I assemble these
  // packets, making sure I assemble the RTP stream in the correct order.
  TIdRTPPacketBuffer = class(TObject)
  private
    List: TObjectList;

    function  AppropriateIndex(Pkt: TIdRTPPacket): Integer;
    procedure Clear;
    function  PacketAt(Index: Integer): TIdRTPPacket;
  public
    constructor Create;
    destructor  Destroy; override;

    procedure Add(Pkt: TIdRTPPacket);
    function  Last: TIdRTPPacket;
    procedure RemoveLast;
  end;

  ENoPayloadTypeFound = class(Exception);
  EStreamTooShort = class(Exception);
  EUnknownSDES = class(Exception);

function  AddModulo(Addend, Augend: Cardinal; Radix: Cardinal): Cardinal;
function  AddModuloWord(Addend, Augend: Word): Word;
function  DateTimeToNTPFractionsOfASecond(DT: TDateTime): Cardinal;
function  DateTimeToNTPSeconds(DT: TDateTime): Cardinal;
function  DateTimeToNTPTimestamp(DT: TDateTime): TIdNTPTimestamp;
function  DateTimeToRTPTimestamp(DT: TDateTime; ClockRate: Cardinal): TIdRTPTimestamp;
function  EncodeAsString(Value: Cardinal): String; overload;
function  EncodeAsString(Value: Word): String; overload;
function  HtoNL(Value: Cardinal): Cardinal;
function  HtoNS(Value: Word): Word;
function  MultiplyCardinal(FirstValue, SecondValue: Cardinal): Cardinal;
function  NowAsNTP: TIdNTPTimestamp;
function  NtoHL(Value: Cardinal): Cardinal;
function  NtoHS(Value: Word): Cardinal;

function  PeekByte(Src: TStream): Byte;
function  PeekWord(Src: TStream): Word;
function  ReadByte(Src: TStream): Byte;
function  ReadCardinal(Src: TStream): Cardinal;
procedure ReadNTPTimestamp(Src: TStream; var Timestamp: TIdNTPTimestamp);
function  ReadRemainderOfStream(Src: TStream): String;
function  ReadString(Src: TStream; Length: Cardinal): String;
function  ReadWord(Src: TStream): Word;
function  TwosComplement(N: Int64): Int64;
procedure WriteByte(Dest: TStream; Value: Byte);
procedure WriteCardinal(Dest: TStream; Value: Cardinal);
procedure WriteNTPTimestamp(Dest: TStream; Value: TIdNTPTimestamp);
procedure WriteString(Dest: TStream; Value: String);
procedure WriteWord(Dest: TStream; Value: Word);

// From RFC 3550 and 3551
const
  RFC3550Version     = 2;
  AudioVisualProfile = 'RTP/AVP';

  CelBEncoding                = 'CelB';
  CNEncoding                  = 'CN';
  DVI4Encoding                = 'DVI4';
  G722Encoding                = 'G722';
  G723Encoding                = 'G723';
  G728Encoding                = 'G728';
  G729Encoding                = 'G729';
  GSMEncoding                 = 'GSM';
  H261Encoding                = 'H261';
  H263Encoding                = 'H263';
  JPEGEncoding                = 'JPEG';
  L16Encoding                 = 'L16';
  LPCEncoding                 = 'LPC';
  MP2TEncoding                = 'MP2T';
  MPAEncoding                 = 'MPA';
  MPVEncoding                 = 'MPV';
  NVEncoding                  = 'nv';
  PCMMuLawEncoding            = 'PCMU';
  PCMALawEncoding             = 'PCMA';
  QCELPEncoding               = 'QCELP';

  RTCPSenderReport       = 200;
  RTCPReceiverReport     = 201;
  RTCPSourceDescription  = 202;
  RTCPGoodbye            = 203;
  RTCPApplicationDefined = 204;

  SDESEnd   = 0;
  SDESCName = 1;
  SDESName  = 2;
  SDESEmail = 3;
  SDESPhone = 4;
  SDESLoc   = 5;
  SDESTool  = 6;
  SDESNote  = 7;
  SDESPriv  = 8;

// From RFC 2793
const
  InterleavedT140ClockRate    = 8000;
  RedundancyEncoding          = 'RED';
  RedundancyEncodingParameter = 'RED';
  T140ClockRate               = 1000;
  T140Encoding                = 'T140';
  T140LostChar                = #$ff#$fd;
  InterleavedT140MimeType     = 'audio/' + T140Encoding;
  RedundantT140MimeType       = 'text/' + RedundancyEncoding;
  T140MimeType                = 'text/' + T140Encoding;

// From RFC 2833
const
  DTMF0                  = 0;
  DTMF1                  = 1;
  DTMF2                  = 2;
  DTMF3                  = 3;
  DTMF4                  = 4;
  DTMF5                  = 5;
  DTMF6                  = 6;
  DTMF7                  = 7;
  DTMF8                  = 8;
  DTMF9                  = 9;
  DTMFStar               = 10;
  DTMFHash               = 11;
  DTMFA                  = 12;
  DTMFB                  = 13;
  DTMFC                  = 14;
  DTMFD                  = 15;
  DTMFFlash              = 16;
  TelephoneEventEncoding = 'telephone-event';
  TelephoneEventMimeType = 'audio/' + TelephoneEventEncoding;

implementation

uses
  DateUtils, IdGlobal, IdHash, IdHashMessageDigest, IdRandom;

var
  GNullEncoding: TIdRTPEncoding;
  GNullPayload:  TIdRTPPayload;

const
  JanOne1900           = 2;
  NTPNegativeTimeError = 'DT < 1900/01/01';
  RTPLoopDetected      = 'RTP loop detected';

//******************************************************************************
//* Unit public functions & procedures                                         *
//******************************************************************************

function AddModulo(Addend, Augend: Cardinal; Radix: Cardinal): Cardinal;
begin
  Result := (Int64(Addend) + Augend) mod Radix
end;

function AddModuloWord(Addend, Augend: Word): Word;
begin
  Result := AddModulo(Addend, Augend, High(Addend));
end;

function DateTimeToNTPFractionsOfASecond(DT: TDateTime): Cardinal;
var
  Divisor:         Int64;
  Fraction:        Double;
  FractionBit:     Cardinal;
  PartOfOneSecond: Double;
begin
  // NTP zero time = 1900/01/01 00:00:00. Since we're working with fractions
  // of a second though we don't care that DT might be before this time.
  
  PartOfOneSecond := MilliSecondOfTheSecond(DT)/1000;
  Result          := 0;
  Divisor         := 2;
  FractionBit     := $80000000;

  while (Divisor <= $40000000) and (PartOfOneSecond > 0) do begin
    Fraction := 1/Divisor;

    if ((PartOfOneSecond - Fraction) >= 0) then begin
      Result := Result or FractionBit;
      PartOfOneSecond := PartOfOneSecond - Fraction;
    end;
    
    FractionBit := FractionBit div 2;
    Divisor := MultiplyCardinal(2, Divisor);
  end;
end;

function DateTimeToNTPSeconds(DT: TDateTime): Cardinal;
var
  Days: Cardinal;
begin
  if (DT < 2) then
    raise EConvertError.Create(NTPNegativeTimeError);

  Days := Trunc(DT) - JanOne1900;

  Result := MultiplyCardinal(Days, SecsPerDay) + SecondOfTheDay(DT);
end;

// Caveat Programmer: TDateTime has the floating point nature. Don't expect
// enormous precision.
// TODO: Maybe we can find a platform-independent way of getting an accurate
// timestamp?
function DateTimeToNTPTimestamp(DT: TDateTime): TIdNTPTimestamp;
begin
  if (DT < 2) then
    raise EConvertError.Create(NTPNegativeTimeError);

  Result.IntegerPart    := DateTimeToNTPSeconds(DT);
  Result.FractionalPart := DateTimeToNTPFractionsOfASecond(DT);
end;

function DateTimeToRTPTimestamp(DT: TDateTime; ClockRate: Cardinal): TIdRTPTimestamp;
var
  Temp: Int64;
begin
  if (DT < 0) then
    raise EConvertError.Create('DateTimeToRTPTimestamp doesn''t support negative timestamps');

  if (ClockRate > 0) then begin
    Temp := Round(ClockRate / OneSecond * DT);
    Result := Temp and $ffffffff;
  end
  else
    Result := 0;
end;

function EncodeAsString(Value: Cardinal): String;
begin
  Result := Chr((Value and $ff000000) shr 24)
          + Chr((Value and $00ff0000) shr 16)
          + Chr((Value and $0000ff00) shr 8)
          + Chr( Value and $000000ff);
end;

function EncodeAsString(Value: Word): String;
begin
  Result := Chr((Value and $ff00) shr 8)
          + Chr( Value and $00ff);
end;

function HtoNL(Value: Cardinal): Cardinal;
begin
  Result := ((Value and $ff000000) shr 24)
         or ((Value and $00ff0000) shr 8)
         or ((Value and $0000ff00) shl 8)
         or ((Value and $000000ff) shl 24);
end;

function HtoNS(Value: Word): Word;
begin
  Result := ((Value and $00ff) shl 8) or ((Value  and $ff00) shr 8);
end;

// Delphi 6 & 7 both compile FirstValue*SecondValue as an imul
// opcode. imul performs a SIGNED integer multiplication, and so if
// FirstValue * SecondValue > $7fffffff then the overflow flag gets set. If you
// have overflow checking on, that means that FOR A PERFECTLY VALID
// multiplication (e.g., $7f000000 * 2) you will get an EIntOverflow.
function MultiplyCardinal(FirstValue, SecondValue: Cardinal): Cardinal;
asm
  mul edx
  jno @end
  call System.@IntOver
 @end:
end;

function NowAsNTP: TIdNTPTimestamp;
begin
  // TODO: This is ugly, but at least it's a bit more portable.
  Result := DateTimeToNTPTimestamp(SysUtils.Now);
end;

function NtoHL(Value: Cardinal): Cardinal;
begin
  Result := HtoNL(Value);
end;

function NtoHS(Value: Word): Cardinal;
begin
  Result := HtoNS(Value);
end;

function PeekByte(Src: TStream): Byte;
begin
  Result := 0;
  Src.Read(Result, SizeOf(Result));
  Src.Seek(-SizeOf(Result), soFromCurrent);
end;

function PeekWord(Src: TStream): Word;
begin
  Result := 0;
  try
    Result := ReadWord(Src);
  except
    on EStreamTooShort do;
  end;
  Src.Seek(-SizeOf(Result), soFromCurrent);
end;

function ReadByte(Src: TStream): Byte;
begin
  if (Src.Read(Result, SizeOf(Result)) < SizeOf(Result)) then
    raise EStreamTooShort.Create('ReadByte');
end;

function ReadCardinal(Src: TStream): Cardinal;
begin
  if (Src.Read(Result, SizeOf(Result)) < SizeOf(Result)) then
    raise EStreamTooShort.Create('ReadCardinal');

  Result := NtoHL(Result);
end;

procedure ReadNTPTimestamp(Src: TStream; var Timestamp: TIdNTPTimestamp);
begin
  Timestamp.IntegerPart    := ReadCardinal(Src);
  Timestamp.FractionalPart := ReadCardinal(Src);
end;

function ReadRemainderOfStream(Src: TStream): String;
const
  BufLen = 100;
var
  Buf:  array[1..BufLen] of Char;
  Read: Integer;
begin
  FillChar(Buf, Length(Buf), 0);
  Result := '';

  repeat
    Read := Src.Read(Buf, BufLen);
    Result := Result + Copy(Buf, 1, Read);
  until (Read < BufLen);
end;

function ReadString(Src: TStream; Length: Cardinal): String;
const
  BufLen = 100;
var
  Buf:   array[1..100] of Char;
  Read:  Integer;
  Total: Cardinal;
begin
  FillChar(Buf, System.Length(Buf), 0);
  Result := '';

  Total := 0;
  repeat
    Read := Src.Read(Buf, Min(BufLen, Length));
    Inc(Total, Read);
    Result := Result + Copy(Buf, 1, Read);
  until (Total >= Length) or (Read = 0);

  if (Total < Length) then
    raise EStreamTooShort.Create('ReadString');
end;

function ReadWord(Src: TStream): Word;
begin
  if (Src.Read(Result, SizeOf(Result)) < SizeOf(Result)) then
    raise EStreamTooShort.Create('ReadWord');

  Result := NtoHS(Result);
end;

function TwosComplement(N: Int64): Int64;
begin
  Result := (not N) + 1;
end;

procedure WriteByte(Dest: TStream; Value: Byte);
begin
  Dest.Write(Value, SizeOf(Value));
end;

procedure WriteCardinal(Dest: TStream; Value: Cardinal);
begin
  Value := HtoNL(Value);
  Dest.Write(Value, SizeOf(Value));
end;

procedure WriteNTPTimestamp(Dest: TStream; Value: TIdNTPTimestamp);
begin
  WriteCardinal(Dest, Value.IntegerPart);
  WriteCardinal(Dest, Value.FractionalPart);
end;

procedure WriteString(Dest: TStream; Value: String);
begin
  if (Value <> '') then
    Dest.Write(Value[1], Length(Value));
end;

procedure WriteWord(Dest: TStream; Value: Word);
begin
  Value := HtoNS(Value);
  Dest.Write(Value, SizeOf(Value));
end;

//******************************************************************************
//* TIdRTPEncoding                                                             *
//******************************************************************************
//* TIdRTPEncoding Public methods **********************************************

class function TIdRTPEncoding.CreateEncoding(Value: String): TIdRTPEncoding;
var
  Name:       String;
  ClockRate:  Cardinal;
  Parameters: String;
begin
  Name       := Fetch(Value, '/');
  ClockRate  := StrToInt(Fetch(Value, '/'));
  Parameters := Value;

  if (Lowercase(Name) = Lowercase(T140Encoding)) then
    Result := TIdT140Encoding.Create(Name,
                                        ClockRate,
                                        Parameters)
  else if (Lowercase(Name) = Lowercase(TelephoneEventEncoding)) then
    Result := TIdTelephoneEventEncoding.Create(Name,
                                                  ClockRate,
                                                  Parameters)
  else
    Result := TIdRTPEncoding.Create(Name,
                                    ClockRate,
                                    Parameters);
end;

class function TIdRTPEncoding.NullEncoding: TIdRTPEncoding;
begin
  if not Assigned(GNullEncoding) then
    GNullEncoding := TIdRTPNullEncoding.Create;

  Result := GNullEncoding;
end;

constructor TIdRTPEncoding.Create(Name: String;
                                  ClockRate: Cardinal;
                                  Parameters: String = '');
begin
  inherited Create;

  fClockRate  := ClockRate;
  fName       := Name;
  fParameters := Parameters;
end;

constructor TIdRTPEncoding.Create(Src: TIdRTPEncoding);
begin
  inherited Create;

  fClockRate  := Src.ClockRate;
  fName       := Src.Name;
  fParameters := Src.Parameters;
end;

function TIdRTPEncoding.AsString: String;
begin
  Result := Self.Name + '/' + IntToStr(Self.ClockRate);

  if (Self.Parameters <> '') then
    Result := Result + '/' + Self.Parameters;
end;

function TIdRTPEncoding.Clone: TIdRTPEncoding;
begin
  Result := TIdRTPEncodingClass(Self.ClassType).Create(Self);
end;

function TIdRTPEncoding.CreatePayload: TIdRTPPayload;
begin
  Result := Self.PayloadType.Create(Self);
end;

function TIdRTPEncoding.IsEqualTo(const OtherEncoding: TIdRTPEncoding): Boolean;
begin
  Result := (Self.Name = OtherEncoding.Name)
        and (Self.ClockRate = OtherEncoding.ClockRate)
        and (Self.Parameters = OtherEncoding.Parameters);
end;

function TIdRTPEncoding.IsNull: Boolean;
begin
  Result := false;
end;

function TIdRTPEncoding.IsReserved: Boolean;
begin
  Result := false;
end;

function TIdRTPEncoding.PayloadType: TIdRTPPayloadClass;
begin
  Result := TIdRawPayload;
end;

//* TIdRTPEncoding Private methods *********************************************

function TIdRTPEncoding.GetName: String;
begin
  Result := fName;
end;

//******************************************************************************
//* TIdT140Encoding                                                            *
//******************************************************************************
//* TIdT140Encoding Public methods *********************************************

function TIdT140Encoding.PayloadType: TIdRTPPayloadClass;
begin
  Result := TIdT140Payload;
end;

//******************************************************************************
//* TIdTelephoneEventEncoding                                                  *
//******************************************************************************
//* TIdTelephoneEventEncoding Public methods ***********************************

function TIdTelephoneEventEncoding.PayloadType: TIdRTPPayloadClass;
begin
  Result := TIdTelephoneEventPayload;
end;

//******************************************************************************
//* TIdRTPNullEncoding                                                         *
//******************************************************************************
//* TIdRTPNullEncoding Public methods ******************************************

constructor TIdRTPNullEncoding.Create(Name: String;
                                      ClockRate: Cardinal;
                                      Parameters: String = '');
begin
  inherited Create('', 0, '');
end;

constructor TIdRTPNullEncoding.Create(Src: TIdRTPEncoding);
begin
  inherited Create('', 0, '');
end;

function TIdRTPNullEncoding.AsString: String;
begin
  Result := '';
end;

function TIdRTPNullEncoding.Clone: TIdRTPEncoding;
begin
  Result := TIdRTPNullEncoding.Create(Self);
end;

function TIdRTPNullEncoding.CreatePayload: TIdRTPPayload;
begin
  Result := TIdNullPayload.NullPayload;
end;

function TIdRTPNullEncoding.IsNull: Boolean;
begin
  Result := true;
end;

//******************************************************************************
//* TIdRTPReservedEncoding                                                     *
//******************************************************************************
//* TIdRTPReservedEncoding Public methods **************************************

constructor TIdRTPReservedEncoding.Create(Name: String;
                                          ClockRate: Cardinal;
                                          Parameters: String = '');
begin
  inherited Create('', 0, '');
end;

constructor TIdRTPReservedEncoding.Create(Src: TIdRTPEncoding);
begin
  inherited Create('', 0, '');
end;

function TIdRTPReservedEncoding.AsString: String;
begin
  Result := '';
end;

function TIdRTPReservedEncoding.Clone: TIdRTPEncoding;
begin
  Result := TIdRTPReservedEncoding.Create(Self);
end;

function TIdRTPReservedEncoding.IsReserved: Boolean;
begin
  Result := true;
end;

//******************************************************************************
//* TIdRTPPayload                                                              *
//******************************************************************************
//* TIdRTPPayload Public methods ***********************************************

class function TIdRTPPayload.CreateFrom(Encoding: TIdRTPEncoding;
                                        Src: TStream): TIdRTPPayload;
begin
  Result := Encoding.CreatePayload;
  try
    Result.ReadFrom(Src);
  except
    FreeAndNil(Result);

    raise;
  end;
end;

class function TIdRTPPayload.NullPayload: TIdRTPPayload;
begin
  if not Assigned(GNullPayload) then
    GNullPayload := TIdNullPayload.Create(TIdRTPEncoding.NullEncoding);

  Result := GNullPayload;
end;

constructor TIdRTPPayload.Create(Encoding: TIdRTPEncoding);
begin
  inherited Create;

  fName           := Encoding.Name;
  Self.ClockRate  := Encoding.ClockRate;
  Self.Parameters := Encoding.Parameters;

  Self.StartTime := Now;

  fEncoding := Encoding;
end;

procedure TIdRTPPayload.Assign(Src: TPersistent);
var
  S: TStream;
begin
  if not (Src is TIdRTPPayload) then
    inherited Assign(Src)
  else begin
    S := TMemoryStream.Create;
    try
      TIdRTPPayload(Src).PrintOn(S);
      S.Seek(0, soFromBeginning);
      Self.ReadFrom(S);
    finally
      S.Free;
    end;
    Self.StartTime := TIdRTPPayload(Src).StartTime;
  end;
end;

function TIdRTPPayload.HasKnownLength: Boolean;
begin
  Result := false;
end;

function TIdRTPPayload.IsNull: Boolean;
begin
  Result := false;
end;

function TIdRTPPayload.Length: Cardinal;
begin
  Result := 0;
end;

function TIdRTPPayload.NumberOfSamples: Cardinal;
begin
  Result := 0;
end;

procedure TIdRTPPayload.ReadFrom(Src: TStream);
begin
end;

procedure TIdRTPPayload.PrintOn(Dest: TStream);
begin
end;

//* TIdRTPPayload Protected methods ********************************************

function TIdRTPPayload.GetStartTime: TDateTime;
begin
  Result := fStartTime;
end;

procedure TIdRTPPayload.SetStartTime(const Value: TDateTime);
begin
  fStartTime := Value;
end;

//******************************************************************************
//* TIdNullPayload                                                             *
//******************************************************************************
//* TIdNullPayload Public methods **********************************************

function TIdNullPayload.IsNull: Boolean;
begin
  Result := true;
end;

//* TIdNullPayload Protected methods *******************************************

function TIdNullPayload.GetStartTime: TDateTime;
begin
  Result := Now;
end;

procedure TIdNullPayload.SetStartTime(const Value: TDateTime);
begin
end;

//******************************************************************************
//* TIdRawPayload                                                              *
//******************************************************************************
//* TIdRawPayload Public methods ***********************************************

function TIdRawPayload.Length: Cardinal;
begin
  Result := System.Length(Self.Data);
end;

procedure TIdRawPayload.ReadFrom(Src: TStream);
begin
  Self.Data := ReadRemainderOfStream(Src);
end;

procedure TIdRawPayload.PrintOn(Dest: TStream);
begin
  WriteString(Dest, Self.Data);
end;

//******************************************************************************
//* TIdT140Payload                                                             *
//******************************************************************************
//* TIdT140Payload Public methods **********************************************

function TIdT140Payload.HasKnownLength: Boolean;
begin
  Result := false;
end;

function TIdT140Payload.Length: Cardinal;
begin
  Result := System.Length(Self.Block);
end;

procedure TIdT140Payload.ReadFrom(Src: TStream);
begin
  Self.Block := ReadRemainderOfStream(Src);
end;

procedure TIdT140Payload.PrintOn(Dest: TStream);
begin
  WriteString(Dest, Self.Block);
end;

//* TIdT140Payload Protected methods *******************************************

function TIdT140Payload.GetName: String;
begin
  Result := T140Encoding;
end;

//******************************************************************************
//* TIdTelephoneEventPayload                                                   *
//******************************************************************************
//* TIdTelephoneEventPayload Public methods ************************************

function TIdTelephoneEventPayload.NumberOfSamples: Cardinal;
begin
  Result := Self.Duration;
end;

procedure TIdTelephoneEventPayload.ReadFrom(Src: TStream);
var
  B: Byte;
begin
  Self.Event := ReadByte(Src);

  B := ReadByte(Src);
  Self.IsEnd       := B and $80 <> 0;
  Self.ReservedBit := B and $40 <> 0;
  Self.Volume      := B and $3F;

  Self.Duration := ReadWord(Src);
end;

procedure TIdTelephoneEventPayload.PrintOn(Dest: TStream);
var
  B: Byte;
begin
  WriteByte(Dest, Self.Event);

  B := Self.Volume;
  if Self.IsEnd then
    B := B or $80;
  WriteByte(Dest, B);

  WriteWord(Dest, Self.Duration);
end;

//* TIdTelephoneEventPayload Protected methods *********************************

function TIdTelephoneEventPayload.GetName: String;
begin
  Result := TelephoneEventEncoding;
end;

//******************************************************************************
//* TIdRTPProfile                                                              *
//******************************************************************************
//* TIdRTPProfile Public methods ***********************************************

constructor TIdRTPProfile.Create;
begin
  inherited Create;

  Self.NullEncoding     := TIdRTPNullEncoding.Create('', 0, '');
  Self.ReservedEncoding := TIdRTPReservedEncoding.Create('', 0, '');
  Self.Initialize;
end;

destructor TIdRTPProfile.Destroy;
begin
  Self.Clear;

  Self.ReservedEncoding.Free;
  Self.NullEncoding.Free;

  inherited Destroy;
end;

procedure TIdRTPProfile.AddEncoding(Encoding: TIdRTPEncoding;
                                    PayloadType: TIdRTPPayloadType);
begin
  if Encoding.IsNull then
    Self.RemoveEncoding(PayloadType)
  else
    Self.AddEncodingAsReference(Encoding.Clone, PayloadType);
end;

procedure TIdRTPProfile.AddEncoding(Name: String;
                                    ClockRate: Cardinal;
                                    Params: String;
                                    PayloadType: TIdRTPPayloadType);
var
  Enc: TIdRTPEncoding;
begin
  Enc := TIdRTPEncoding.Create(Name, ClockRate, Params);
  try
    Self.AddEncoding(Enc, PayloadType);
  finally
    Enc.Free;
  end;
end;

function TIdRTPProfile.AllowsHeaderExtensions: Boolean;
begin
  Result := true;
end;

procedure TIdRTPProfile.Assign(Src: TPersistent);
var
  I:            TIdRTPPayloadType;
  OtherProfile: TIdRTPProfile;
begin
  if (Src is TIdRTPProfile) then begin
    OtherProfile := Src as TIdRTPProfile;

    for I := Low(TIdRTPPayloadType) to High(TIdRTPPayloadType) do
      Self.AddEncoding(OtherProfile.EncodingFor(I), I);
  end
  else
    inherited Assign(Src);
end;

procedure TIdRTPProfile.Clear;
var
  I: TIdRTPPayloadType;
begin
  for I := Low(TIdRTPPayloadType) to High(TIdRTPPayloadType) do
    if not Self.EncodingFor(I).IsNull and not Self.EncodingFor(I).IsReserved then
      Self.RemoveEncoding(I);
end;

function TIdRTPProfile.Count: Integer;
var
  I: TIdRTPPayloadType;
begin
  Result := 0;
  for I := Low(TIdRTPPayloadType) to High(TIdRTPPayloadType) do
    if not Self.EncodingFor(I).IsNull then Inc(Result);
end;

function TIdRTPProfile.CreatePacket(Src: TStream): TIdRTPBasePacket;
var
  PacketType: Byte;
begin
  PacketType := Self.StreamContainsPayloadType(Src);

  if Self.IsRTCPPayloadType(PacketType) then
    Result := TIdCompoundRTCPPacket.Create
  else
    Result := TIdRTPPacket.Create(Self);
end;

function TIdRTPProfile.EncodingFor(PayloadType: TIdRTPPayloadType): TIdRTPEncoding;
begin
  Result := Self.Encodings[PayloadType] as TIdRTPEncoding;
end;

function TIdRTPProfile.EncodingFor(EncodingName: String): TIdRTPEncoding;
var
  I: Integer;
begin
  Result := Self.NullEncoding;
  I := Low(Self.Encodings);
  while (I <= High(Self.Encodings)) and Result.IsNull do
    if (Self.Encodings[I].AsString = EncodingName) then
      Result := Self.Encodings[I]
    else
      Inc(I);
end;

function TIdRTPProfile.FirstFreePayloadType: TIdRTPPayloadType;
var
  I: Cardinal;
begin
  I := 0;
  while (I <= High(TIdRTPPayloadType)) and not Self.EncodingFor(I).IsNull do
    Inc(I);

  Result := TIdRTPPayloadType(I);
end;

function TIdRTPProfile.HasEncoding(const Encoding: TIdRTPEncoding): Boolean;
begin
  Result := not Encoding.IsNull and (Self.IndexOfEncoding(Encoding) <> -1);
end;

function TIdRTPProfile.HasPayloadType(PayloadType: TIdRTPPayloadType): Boolean;
begin
  Result := not Self.EncodingFor(PayloadType).IsNull;
end;

function TIdRTPProfile.IsFull: Boolean;
var
  I: TIdRTPPayloadType;
begin
  Result := true;

  for I := Low(TIdRTPPayloadType) to High(TIdRTPPayloadType) do begin
    Result := Result and not Self.EncodingFor(I).IsNull;
    if not Result then Break;
  end;
end;

function TIdRTPProfile.IsRTCPPayloadType(const PayloadType: Byte): Boolean;
begin
  Result := (PayloadType >= RTCPSenderReport)
        and (PayloadType <= RTCPApplicationDefined);
end;

function TIdRTPProfile.PayloadTypeFor(Encoding: TIdRTPEncoding): TIdRTPPayloadType;
var
  Index: Integer;
begin
  Index := Self.IndexOfEncoding(Encoding);

  if (Index = -1) then
    raise ENoPayloadTypeFound.Create(Encoding.AsString)
  else
    Result := TIdRTPPayloadType(Index);
end;

function TIdRTPProfile.StreamContainsEncoding(Src: TStream): TIdRTPEncoding;
begin
  Result := Self.EncodingFor(Self.StreamContainsPayloadType(Src));
end;

function TIdRTPProfile.StreamContainsPayloadType(Src: TStream): TIdRTPPayloadType;
var
  FirstWord: Word;
begin
  FirstWord := PeekWord(Src);
  Result := FirstWord and $00ff;
end;

function TIdRTPProfile.TransportDesc: String;
begin
  Result := '';
end;

//* TIdRTPProfile Protected methods ********************************************

procedure TIdRTPProfile.AddEncodingAsReference(Encoding: TIdRTPEncoding;
                                               PayloadType: TIdRTPPayloadType);
begin
  if not Self.HasPayloadType(PayloadType) and not Self.HasEncoding(Encoding) then
    Self.Encodings[PayloadType] := Encoding;
end;

procedure TIdRTPProfile.ReservePayloadType(const PayloadType: TIdRTPPayloadType);
begin
  if    (Self.Encodings[PayloadType] <> Self.NullEncoding)
    and (Self.Encodings[PayloadType] <> Self.ReservedEncoding) then
    Self.Encodings[PayloadType].Free;

  Self.Encodings[PayloadType] := Self.ReservedEncoding;
end;

//* TIdRTPProfile Private methods **********************************************

function TIdRTPProfile.IndexOfEncoding(const Encoding: TIdRTPEncoding): Integer;
begin
  Result := 0;

  while (Result <= High(TIdRTPPayloadType))
    and not Self.EncodingFor(Result).IsEqualTo(Encoding) do
      Inc(Result);

  if (Result > High(TIdRTPPayloadType)) then
    Result := -1;
end;

procedure TIdRTPProfile.Initialize;
var
  I: TIdRTPPayloadType;
begin
  for I := Low(TIdRTPPayloadType) to High(TIdRTPPayloadType) do
    Self.Encodings[I] := Self.NullEncoding;
end;

procedure TIdRTPProfile.RemoveEncoding(const PayloadType: TIdRTPPayloadType);
begin
  if    (Self.Encodings[PayloadType] <> Self.NullEncoding)
    and (Self.Encodings[PayloadType] <> Self.ReservedEncoding) then begin
    Self.Encodings[PayloadType].Free;
    Self.Encodings[PayloadType] := Self.NullEncoding;
  end;
end;

//******************************************************************************
//* TIdAudioVisualProfile                                                      *
//******************************************************************************
//* TIdAudioVisualProfile Public methods ***************************************

constructor TIdAudioVisualProfile.Create;
begin
  inherited Create;

  Self.AddEncodingAsReference(TIdRTPEncoding.Create(PCMMuLawEncoding, 8000),        0);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(GSMEncoding,      8000),        3);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(G723Encoding,     8000),        4);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(DVI4Encoding,     8000),        5);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(DVI4Encoding,     16000),       6);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(LPCEncoding,      8000),        7);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(PCMALawEncoding,  8000),        8);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(G722Encoding,     8000),        9);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(L16Encoding,      44100, '2'), 10);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(L16Encoding,      44100, '1'), 11);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(QCELPEncoding,    8000),       12);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(CNEncoding,       8000),       13);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(MPAEncoding,      90000),      14);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(G728Encoding,     8000),       15);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(DVI4Encoding,     11025),      16);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(DVI4Encoding,     22050),      17);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(G729Encoding,     8000),       18);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(CelBEncoding,     90000),      25);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(JPEGEncoding,     90000),      26);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(NVEncoding,       90000),      28);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(H261Encoding,     90000),      31);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(MPVEncoding,      90000),      32);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(MP2TEncoding,     90000),      33);
  Self.AddEncodingAsReference(TIdRTPEncoding.Create(H263Encoding,     90000),      34);

  Self.ReserveRange(1,  2);
  Self.ReserveRange(19, 24);

  Self.ReservePayloadType(27);

  Self.ReserveRange(29, 30);
  Self.ReserveRange(35, 95);
end;

procedure TIdAudioVisualProfile.Assign(Src: TPersistent);
var
  I:            TIdRTPPayloadType;
  OtherProfile: TIdRTPProfile;
begin
  if (Src is TIdRTPProfile) then begin
    OtherProfile := Src as TIdRTPProfile;

    for I := 96 to 127 do
      Self.AddEncoding(OtherProfile.EncodingFor(I), I);
  end
  else
    inherited Assign(Src);
end;

function TIdAudioVisualProfile.TransportDesc: String;
begin
  Result := AudioVisualProfile;
end;

//* TIdAudioVisualProfile Private methods **************************************

procedure TIdAudioVisualProfile.ReserveRange(LowPT, HighPT: TIdRTPPayloadType);
var
  I: TIdRTPPayloadType;
begin
  for I := LowPT to HighPT do
    Self.ReservePayloadType(I);
end;

//******************************************************************************
//* TIdRTPHeaderExtension                                                      *
//******************************************************************************
//* TIdRTPHeaderExtension Public methods ***************************************

function TIdRTPHeaderExtension.OctetCount: Cardinal;
begin
  Result := 4*Self.Length + 4;
end;

procedure TIdRTPHeaderExtension.ReadFrom(Src: TStream);
var
  I: Integer;
begin
  Self.ProfileDefinedValue := ReadWord(Src);
  Self.Length              := ReadWord(Src);

  for I := 0 to Self.Length - 1 do
    Self.Data[I] := ReadCardinal(Src);
end;

procedure TIdRTPHeaderExtension.PrintOn(Dest: TStream);
var
  I: Integer;
begin
  WriteWord(Dest, Self.ProfileDefinedValue);
  WriteWord(Dest, Self.Length);

  for I := 0 to Self.Length - 1 do
    WriteCardinal(Dest, Self.Data[I]);
end;

//* TIdRTPHeaderExtension Private methods ***************************************

function TIdRTPHeaderExtension.GetData(Index: Word): Cardinal;
begin
  Result := fData[Index];
end;

function TIdRTPHeaderExtension.GetLength: Word;
begin
  Result := System.Length(fData);
end;

procedure TIdRTPHeaderExtension.SetData(Index: Word; const Value: Cardinal);
begin
  fData[Index] := Value;
end;

procedure TIdRTPHeaderExtension.SetLength(const Value: Word);
begin
  System.SetLength(fData, Value);
end;

//******************************************************************************
//* TIdRTCPReportBlock                                                         *
//******************************************************************************
//* TIdRTCPReportBlock Public methods ******************************************

procedure TIdRTCPReportBlock.GatherStatistics(Member: TIdRTPMember);
begin
  Self.CumulativeLoss     := Member.PacketLossCount;
  Self.DelaySinceLastSR   := Member.DelaySinceLastSenderReport;
  Self.FractionLost       := Member.PacketLossFraction;
  Self.HighestSeqNo       := Member.HighestSeqNo;
  Self.InterArrivalJitter := Member.Jitter;
  Self.LastSenderReport   := Member.LastSenderReport;
  Self.SyncSrcID          := Member.SyncSrcID;
end;

procedure TIdRTCPReportBlock.PrintOn(Dest: TStream);
var
  Loss: Cardinal;
begin
  WriteCardinal(Dest, Self.SyncSrcID);
  Loss := (Self.FractionLost shl 24) or Self.CumulativeLoss;
  WriteCardinal(Dest, Loss);
  WriteCardinal(Dest, Self.HighestSeqNo);
  WriteCardinal(Dest, Self.InterArrivalJitter);
  WriteCardinal(Dest, Self.LastSenderReport);
  WriteCardinal(Dest, Self.DelaySinceLastSR);
end;

procedure TIdRTCPReportBlock.ReadFrom(Src: TStream);
var
  Loss: Cardinal;
begin
  Self.SyncSrcID          := ReadCardinal(Src);
  Loss                    := ReadCardinal(Src);
  Self.FractionLost       := Loss shr 24;
  Self.CumulativeLoss     := Loss and $00ffffff;
  Self.HighestSeqNo       := ReadCardinal(Src);
  Self.InterArrivalJitter := ReadCardinal(Src);
  Self.LastSenderReport   := ReadCardinal(Src);
  Self.DelaySinceLastSR   := ReadCardinal(Src);
end;

//******************************************************************************
//* TIdRTPBasePacket                                                           *
//******************************************************************************
//* TIdRTPBasePacket Public methods ********************************************

constructor TIdRTPBasePacket.Create;
begin
  Self.Version := RFC3550Version;
end;

procedure TIdRTPBasePacket.Assign(Src: TPersistent);
var
  S: TStringStream;
begin
  if Src.ClassType <> Self.ClassType then
    inherited Assign(Src)
  else begin
    if Src is TIdRTPBasePacket then begin
      S := TStringStream.Create('');
      try
        TIdRTPBasePacket(Src).PrintOn(S);
        S.Seek(0, soFromBeginning);
        Self.ReadFrom(S);
      finally
        S.Free;
      end;
    end;
  end;
end;

procedure TIdRTPBasePacket.PrepareForTransmission(Session: TIdRTPSession);
begin
  Self.SyncSrcID := Session.SyncSrcID;
end;

//* TIdRTPBasePacket Protected methods *****************************************

function TIdRTPBasePacket.GetSyncSrcID: Cardinal;
begin
  Result := fSyncSrcID;
end;

procedure TIdRTPBasePacket.PrintPadding(Dest: TStream);
var
  I:         Integer;
  PadLength: Byte;
begin
  //   padding (P): 1 bit
  //      If the padding bit is set, this individual RTCP packet contains
  //      some additional padding octets at the end which are not part of
  //      the control information but are included in the length field.  The
  //      last octet of the padding is a count of how many padding octets
  //      should be ignored, including itself (it will be a multiple of
  //      four).
  Assert(Self.Length > Self.RealLength,
         'Length must be set before padding is printed');
  Assert((Self.Length - Self.RealLength) mod 4 = 0,
         'Padding must be a multiple of 4');

  // RFC 3550, section 4: "Octets designated as padding have the value zero."
  PadLength := Self.Length - Self.RealLength;
  for I := 1 to PadLength - 1 do
    WriteByte(Dest, 0);

  // The written padding length includes itself
  WriteByte(Dest, PadLength);
end;

procedure TIdRTPBasePacket.SetSyncSrcID(const Value: Cardinal);
begin
  fSyncSrcID := Value;
end;

//******************************************************************************
//* TIdRTPPacket                                                               *
//******************************************************************************
//* TIdRTPPacket Public methods ************************************************

constructor TIdRTPPacket.Create(Profile: TIdRTPProfile);
begin
  inherited Create;

  fHeaderExtension := TIdRTPHeaderExtension.Create;
  fPayload         := TIdRTPPayload.NullPayload;

  Self.Profile := Profile;
  Self.Version := Self.DefaultVersion;
end;

destructor TIdRTPPacket.Destroy;
begin
  fHeaderExtension.Free;

  if not Self.Payload.IsNull then
    Self.Payload.Free;

  inherited Destroy;
end;

function TIdRTPPacket.Clone: TIdRTPBasePacket;
begin
  Result := TIdRTPPacket.Create(Self.Profile);
  Result.Assign(Self);
end;

function TIdRTPPacket.CollidesWith(SSRC: Cardinal): Boolean;
var
  I: Integer;
begin
  Result := Self.SyncSrcID = SSRC;
  for I := 0 to Self.CsrcCount - 1 do
    Result := Result or (Self.CsrcIDs[I] = SSRC);
end;

function TIdRTPPacket.GetAllSrcIDs: TCardinalDynArray;
var
  I: Integer;
begin
  // Return an array with all the source identifiers mentioned in this packet.
  // This boils down to the SSRC of the sender + the set of CSRCs
  SetLength(Result, Self.CsrcCount + 1);
  Result[0] := Self.SyncSrcID;

  for I := 0 to Self.CsrcCount - 1 do
    Result[I + 1] := Self.CsrcIDs[I];
end;

function TIdRTPPacket.IsRTCP: Boolean;
begin
  Result := false;
end;

function TIdRTPPacket.IsRTP: Boolean;
begin
  Result := true;
end;

function TIdRTPPacket.IsValid: Boolean;
begin
  Result := (Self.Version = RFC3550Version)
         and Self.Profile.HasPayloadType(Self.PayloadType)
         and (Self.Profile.AllowsHeaderExtensions or not Self.HasExtension);
end;

procedure TIdRTPPacket.PrepareForTransmission(Session: TIdRTPSession);
begin
  inherited PrepareForTransmission(Session);

  Self.SequenceNo := Session.NextSequenceNo;

  Self.Timestamp := DateTimeToRTPTimestamp(Session.TimeOffsetFromStart(Self.Payload.StartTime),
                                           Self.Payload.Encoding.ClockRate);
end;

procedure TIdRTPPacket.PrintOn(Dest: TStream);
var
  B: Byte;
  I: Integer;
begin
  B := Self.Version shl 6;
  if Self.HasPadding then B := B or $20;
  if Self.HasExtension then B := B or $10;
  B := B or Self.CsrcCount;
  WriteByte(Dest, B);

  B := Self.PayloadType;
  if Self.IsMarker then B := B or $80;
  WriteByte(Dest, B);

  WriteWord(Dest, Self.SequenceNo);

  WriteCardinal(Dest, Self.Timestamp);
  WriteCardinal(Dest, Self.SyncSrcID);

  for I := 0 to Self.CsrcCount - 1 do
    WriteCardinal(Dest, Self.CsrcIDs[I]);

  if Self.HasExtension then
    Self.HeaderExtension.PrintOn(Dest);

  Self.Payload.PrintOn(Dest);

  if Self.HasPadding then
    Self.PrintPadding(Dest);
end;

procedure TIdRTPPacket.ReadFrom(Src: TStream);
var
  B: Byte;
  I: TIdRTPCsrcCount;
begin
  // Populate Self's properties etc from the RTP packet in Src.
  // Self.Profile knows what packet types map to what encodings,
  // so we can read in the entire RTP packet (payload and all) as
  // long as the packet type has been mapped to an encoding.
  // Should the raw payload be used, we treat the entire stream as
  // the payload. This seems the only reasonable course of action.

  B := ReadByte(Src);
  Self.Version      := (B and $C0) shr 6;
  Self.HasPadding   := (B and $20) <> 0;
  Self.HasExtension := (B and $10) <> 0;
  Self.CsrcCount    :=  B and $0F;

  B := ReadByte(Src);
  Self.IsMarker    := (B and $80) <> 0;
  Self.PayloadType :=  B and $7F;

  Self.SequenceNo := ReadWord(Src);
  Self.Timestamp  := ReadCardinal(Src);
  Self.SyncSrcID  := ReadCardinal(Src);

  // Remember that the first Csrc = Self.SyncSrcID
  for I := 1 to Self.CsrcCount do
    Self.CsrcIDs[I - 1] := ReadCardinal(Src);

  if Self.HasExtension then
    Self.HeaderExtension.ReadFrom(Src);

  if Self.HasPadding then
    Self.ReadPayloadAndPadding(Src, Self.Profile)
  else
    Self.ReadPayload(Src, Self.Profile);
end;

procedure TIdRTPPacket.ReadPayload(Src: TStream;
                                   Profile: TIdRTPProfile);
begin
  Self.ReplacePayload(Profile.EncodingFor(Self.PayloadType));
  Self.Payload.ReadFrom(Src);
end;

procedure TIdRTPPacket.ReadPayload(Src: String;
                                   Profile: TIdRTPProfile);
var
  S: TStringStream;
begin
  S := TStringStream.Create(Src);
  try
    Self.ReadPayload(S, Profile);
  finally
    S.Free;
  end;
end;

procedure TIdRTPPacket.ReadPayload(Data: TIdRTPPayload);
begin
  Self.PayloadType := Self.Profile.PayloadTypeFor(Data.Encoding);
  Self.ReplacePayload(Data.Encoding);
  Self.Payload.Assign(Data);
end;

function TIdRTPPacket.RealLength: Word;
begin
  Result := 12
          + Self.CsrcCount*4
          + Self.Payload.Length;

  if Self.HasExtension then
    Result := Result + Self.HeaderExtension.OctetCount;
end;

//* TIdRTPPacket Private methods ***********************************************

function TIdRTPPacket.DefaultVersion: TIdRTPVersion;
begin
  Result := 2;
end;

function TIdRTPPacket.GetCsrcCount: TIdRTPCsrcCount;
begin
  Result := fCsrcCount;
end;

function TIdRTPPacket.GetCsrcID(Index: TIdRTPCsrcCount): Cardinal;
begin
  Result := fCsrcIDs[Index];
end;

procedure TIdRTPPacket.ReadPayloadAndPadding(Src: TStream;
                                             Profile: TIdRTPProfile);
var
  CurrentPos:    Int64;
  Padding:       Byte;
  PayloadStream: TMemoryStream;
begin
  CurrentPos := Src.Position;
  Src.Seek(1, soFromEnd);
  Padding := ReadByte(Src);
  Src.Seek(CurrentPos, soFromBeginning);

  PayloadStream := TMemoryStream.Create;
  try
    PayloadStream.CopyFrom(Src, Src.Size - Src.Position - Padding);
    PayloadStream.Seek(0, soFromBeginning);
    Self.ReadPayload(PayloadStream, Self.Profile);
  finally
    PayloadStream.Free;
  end;
end;

procedure TIdRTPPacket.ReplacePayload(const Encoding: TIdRTPEncoding);
begin
  if (Self.Payload <> TIdRTPPayload.NullPayload) then
    fPayload.Free;

  fPayload := Encoding.CreatePayload;
end;

procedure TIdRTPPacket.SetCsrcCount(const Value: TIdRTPCsrcCount);
begin
  fCsrcCount := Value;

  SetLength(fCsrcIDs, Value);
end;

procedure TIdRTPPacket.SetCsrcID(Index: TIdRTPCsrcCount; const Value: Cardinal);
begin
  fCsrcIDs[Index] := Value;
end;

//******************************************************************************
//* TIdRTCPPacket                                                              *
//******************************************************************************
//* TIdRTCPPacket Public methods ***********************************************

class function TIdRTCPPacket.RTCPType(const PacketType: Byte): TIdRTCPPacketClass;
begin
  case PacketType of
    RTCPSenderReport:       Result := TIdRTCPSenderReport;
    RTCPReceiverReport:     Result := TIdRTCPReceiverReport;
    RTCPSourceDescription:  Result := TIdRTCPSourceDescription;
    RTCPGoodbye:            Result := TIdRTCPBye;
    RTCPApplicationDefined: Result := TIdRTCPApplicationDefined;
  else
    // Maybe we should have an TIdRTCPUnknown?
    Result := nil;
  end;
end;

constructor TIdRTCPPacket.Create;
begin
  inherited Create;
end;

function TIdRTCPPacket.Clone: TIdRTPBasePacket;
begin
  Result := TIdRTCPPacket.RTCPType(Self.PacketType).Create;
  Result.Assign(Self);
end;

function TIdRTCPPacket.IsBye: Boolean;
begin
  Result := false;
end;

function TIdRTCPPacket.IsReceiverReport: Boolean;
begin
  Result := false;
end;

function TIdRTCPPacket.IsRTCP: Boolean;
begin
  Result := true;
end;

function TIdRTCPPacket.IsRTP: Boolean;
begin
  Result := false;
end;

function TIdRTCPPacket.IsSenderReport: Boolean;
begin
  Result := false;
end;

function TIdRTCPPacket.IsSourceDescription: Boolean;
begin
  Result := false;
end;

function TIdRTCPPacket.IsValid: Boolean;
begin
  Result := Self.Version = RFC3550Version;
end;

//* TIdRTCPPacket Protected methods ********************************************

procedure TIdRTCPPacket.AssertPacketType(const PT: Byte);
begin
  Assert(PT = Self.GetPacketType,
         Self.ClassName + ' packet type');
end;

//******************************************************************************
//* TIdRTCPReceiverReport                                                      *
//******************************************************************************
//* TIdRTCPReceiverReport Public methods ***************************************

function TIdRTCPReceiverReport.GetAllSrcIDs: TCardinalDynArray;
var
  I, J: Integer;
begin
  SetLength(Result, Self.ReceptionReportCount + 1);
  Result[Low(Result)] := Self.SyncSrcID;

  J := Low(Result) + 1;
  for I := 0 to Self.ReceptionReportCount - 1 do begin
    Result[J] := Self.Reports[I].SyncSrcID;
    Inc(J);
  end;
end;

function TIdRTCPReceiverReport.IsReceiverReport: Boolean;
begin
  Result := true;
end;

procedure TIdRTCPReceiverReport.PrintOn(Dest: TStream);
var
  I: Integer;
begin
  Self.PrintFixedHeadersOn(Dest);

  for I := 0 to Self.ReceptionReportCount - 1 do
    Self.Reports[I].PrintOn(Dest);

  if Self.HasPadding then
    Self.PrintPadding(Dest);
end;

procedure TIdRTCPReceiverReport.ReadFrom(Src: TStream);
begin
  Self.ReadFixedHeadersFrom(Src);
  Self.ReadAllReportBlocks(Src);
end;

function TIdRTCPReceiverReport.RealLength: Word;
begin
  Result := Self.FixedHeaderByteLength
          + Self.ReceptionReportCount * Self.ReportByteLength
          + Abs(System.Length(Self.Extension));
end;

//* TIdRTCPReceiverReport Protected methods ************************************

function TIdRTCPReceiverReport.FixedHeaderByteLength: Word;
begin
  Result := 2*4;
end;

function TIdRTCPReceiverReport.GetPacketType: Cardinal;
begin
  Result := RTCPReceiverReport;
end;

procedure TIdRTCPReceiverReport.PrintFixedHeadersOn(Dest: TStream);
var
  B: Byte;
begin
  B := Self.Version shl 6;
  if Self.HasPadding then B := B or $20;
  B := B or Self.ReceptionReportCount;
  WriteByte(Dest, B);

  WriteByte(Dest, Self.GetPacketType);

  WriteWord(Dest, Self.Length);
  WriteCardinal(Dest, Self.SyncSrcID);
end;

procedure TIdRTCPReceiverReport.ReadFixedHeadersFrom(Src: TStream);
var
  B: Byte;
begin
  B := ReadByte(Src);
  Self.Version              := B shr 6;
  Self.HasPadding           := (B and $20) > 0;
  Self.ReceptionReportCount := B and $1F;
  Self.AssertPacketType(ReadByte(Src));

  Self.Length    := ReadWord(Src);
  Self.SyncSrcID := ReadCardinal(Src);
end;

//* TIdRTCPReceiverReport Private methods **************************************

procedure TIdRTCPReceiverReport.ClearReportBlocks;
var
  I: Integer;
begin
  for I := Low(fReceptionReports) to High(fReceptionReports) do
    fReceptionReports[I].Free;
end;

function TIdRTCPReceiverReport.GetReports(Index: Integer): TIdRTCPReportBlock;
begin
  if (Index < 0) or (Index >= Self.ReceptionReportCount) then
    raise EListError.Create('List index out of bounds (' + IntToStr(Index) + ')');

  Result := fReceptionReports[Index];
end;

function TIdRTCPReceiverReport.GetReceptionReportCount: TIdRTCPReceptionCount;
begin
  Result := System.Length(fReceptionReports);
end;

procedure TIdRTCPReceiverReport.ReadAllReportBlocks(Src: TStream);
var
  I: Integer;
begin
  for I := Low(fReceptionReports) to High(fReceptionReports) do
    fReceptionReports[I].ReadFrom(Src);
end;

function TIdRTCPReceiverReport.ReportByteLength: Word;
begin
  Result := 6*4;
end;

procedure TIdRTCPReceiverReport.ReInitialiseReportBlocks;
var
  I: Integer;
begin
  for I := Low(fReceptionReports) to High(fReceptionReports) do
    fReceptionReports[I] := TIdRTCPReportBlock.Create;
end;

procedure TIdRTCPReceiverReport.SetReceptionReportCount(const Value: TIdRTCPReceptionCount);
begin
  Self.ClearReportBlocks;
  SetLength(fReceptionReports, Value);
  Self.ReInitialiseReportBlocks;
end;

//******************************************************************************
//* TIdRTCPSenderReport                                                        *
//******************************************************************************
//* TIdRTCPSenderReport Public methods *****************************************

destructor TIdRTCPSenderReport.Destroy;
begin
  Self.ClearReportBlocks;

  inherited Destroy;
end;

function TIdRTCPSenderReport.IsReceiverReport: Boolean;
begin
  // We inherit from ReceiverReport for code reuse ONLY. A Sender Report
  // IS NOT a Receiver Report. TODO: This indicates ugliness.
  // SR/RR relationship needs revisiting, possibly using delegation for
  // common behaviour, rather than inheritance.
  Result := false;
end;

function TIdRTCPSenderReport.IsSenderReport: Boolean;
begin
  Result := true;
end;

procedure TIdRTCPSenderReport.PrepareForTransmission(Session: TIdRTPSession);
begin
  inherited PrepareForTransmission(Session);
  Self.NTPTimestamp := NowAsNTP;
end;

//* TIdRTCPSenderReport Protected methods **************************************

function TIdRTCPSenderReport.FixedHeaderByteLength: Word;
begin
  Result := 7*4;
end;

function TIdRTCPSenderReport.GetPacketType: Cardinal;
begin
  Result := RTCPSenderReport;
end;

procedure TIdRTCPSenderReport.PrintFixedHeadersOn(Dest: TStream);
begin
  inherited PrintFixedHeadersOn(Dest);

  WriteNTPTimestamp(Dest, Self.NTPTimestamp);
  WriteCardinal(Dest, Self.RTPTimestamp);
  WriteCardinal(Dest, Self.PacketCount);
  WriteCardinal(Dest, Self.OctetCount);
end;

procedure TIdRTCPSenderReport.ReadFixedHeadersFrom(Src: TStream);
var
  T: TIdNTPTimestamp;
begin
  inherited ReadFixedHeadersFrom(Src);
  
  T.IntegerPart     := ReadCardinal(Src);
  T.FractionalPart  := ReadCardinal(Src);
  Self.NTPTimestamp := T;
  Self.RTPTimestamp := ReadCardinal(Src);
  Self.PacketCount  := ReadCardinal(Src);
  Self.OctetCount   := ReadCardinal(Src);
end;

//******************************************************************************
//* TIdSrcDescChunkItem                                                        *
//******************************************************************************
//* TIdSrcDescChunkItem Public methods *****************************************

class function TIdSrcDescChunkItem.ItemType(ID: Byte): TIdSrcDescChunkItemClass;
begin
  case ID of
    SDESCName: Result := TIdSDESCanonicalName;
    SDESName:  Result := TIdSDESUserName;
    SDESEmail: Result := TIdSDESEmail;
    SDESPhone: Result := TIdSDESPhone;
    SDESLoc:   Result := TIdSDESLocation;
    SDESTool:  Result := TIdSDESTool;
    SDESNote:  Result := TIdSDESNote;
    SDESPriv:  Result := TIdSDESPriv;
  else
    raise EUnknownSDES.Create('Unknown SDES type ' + IntToStr(ID));
  end;
end;

function TIdSrcDescChunkItem.Length: Byte;
begin
  Result := System.Length(Self.Data);
end;

procedure TIdSrcDescChunkItem.PrintOn(Dest: TStream);
begin
  WriteByte(Dest, Self.ID);
  WriteByte(Dest, Self.Length);
  WriteString(Dest, Self.Data);
end;

procedure TIdSrcDescChunkItem.ReadFrom(Src: TStream);
var
  ID:  Byte;
  Len: Byte;
begin
  ID := ReadByte(Src);
  Assert(ID = Self.ID, Self.ClassName + ' SDES item ID');

  Len := ReadByte(Src);
  Self.Data := ReadString(Src, Len);
end;

function TIdSrcDescChunkItem.RealLength: Cardinal;
begin
  Result := 2 + System.Length(Self.Data);
end;

//* TIdSrcDescChunkItem Protected methods **************************************

procedure TIdSrcDescChunkItem.SetData(const Value: String);
begin
  fData := Copy(Value, 1, High(Self.Length));
end;

//******************************************************************************
//* TIdSDESCanonicalName                                                       *
//******************************************************************************
//* TIdSDESCanonicalName Public methods ****************************************

function TIdSDESCanonicalName.ID: Byte;
begin
  Result := SDESCName;
end;

//******************************************************************************
//* TIdSDESUserName                                                            *
//******************************************************************************
//* TIdSDESUserName Public methods *********************************************

function TIdSDESUserName.ID: Byte;
begin
  Result := SDESName;
end;

//******************************************************************************
//* TIdSDESEmail                                                               *
//******************************************************************************
//* TIdSDESEmail Public methods ************************************************

function TIdSDESEmail.ID: Byte;
begin
  Result := SDESEmail;
end;

//******************************************************************************
//* TIdSDESPhone                                                               *
//******************************************************************************
//* TIdSDESPhone Public methods ************************************************

function TIdSDESPhone.ID: Byte;
begin
  Result := SDESPhone;
end;

//******************************************************************************
//* TIdSDESLocation                                                            *
//******************************************************************************
//* TIdSDESLocation Public methods *********************************************

function TIdSDESLocation.ID: Byte;
begin
  Result := SDESLoc;
end;

//******************************************************************************
//* TIdSDESTool                                                                *
//******************************************************************************
//* TIdSDESTool Public methods *************************************************

function TIdSDESTool.ID: Byte;
begin
  Result := SDESTool;
end;

//******************************************************************************
//* TIdSDESNote                                                                *
//******************************************************************************
//* TIdSDESNote Public methods *************************************************

function TIdSDESNote.ID: Byte;
begin
  Result := SDESNote;
end;

//******************************************************************************
//* TIdSDESPriv                                                                *
//******************************************************************************
//* TIdSDESPriv Public methods *************************************************

function TIdSDESPriv.ID: Byte;
begin
  Result := SDESPriv;
end;

procedure TIdSDESPriv.PrintOn(Dest: TStream);
begin
  WriteByte(Dest, Self.ID);
  WriteByte(Dest, Self.Length + System.Length(Self.Prefix) + 1);
  WriteByte(Dest, System.Length(Self.Prefix));

  WriteString(Dest, Self.Prefix);
  WriteString(Dest, Self.Data);
end;

procedure TIdSDESPriv.ReadFrom(Src: TStream);
var
  PrefixLen: Byte;
begin
  inherited ReadFrom(Src);

  if (Self.Data = '') then
    raise EStreamTooShort.Create('Missing prefix length');

  PrefixLen := Ord(Self.Data[1]);
  Self.Data := Copy(Self.Data, 2, System.Length(Self.Data));
  Self.Prefix := Copy(Self.Data, 1, PrefixLen);
  Self.Data := Copy(Self.Data, PrefixLen + 1, System.Length(Self.Data));
end;

function TIdSDESPriv.RealLength: Cardinal;
begin
  Result := 3 + System.Length(Self.Prefix) + System.Length(Self.Data);
end;

//* TIdSDESPriv Protected methods **********************************************

procedure TIdSDESPriv.SetData(const Value: String);
begin
  inherited SetData(Copy(Value, 1, Self.MaxDataLength));
end;

//* TIdSDESPriv Private methods ************************************************

function TIdSDESPriv.MaxDataLength: Byte;
begin
  Result := Self.MaxPrefixLength - System.Length(Self.Prefix);
end;

function TIdSDESPriv.MaxPrefixLength: Byte;
begin
  Result := High(Byte) - 1;
end;

procedure TIdSDESPriv.SetPrefix(const Value: String);
begin
  fPrefix := Copy(Value, 1, Self.MaxPrefixLength);

  Self.TruncateData;
end;

procedure TIdSDESPriv.TruncateData;
begin
  if (Self.Data <> '') then
    Self.Data := Self.Data;
end;

//******************************************************************************
//* TIdRTCPSrcDescChunk                                                        *
//******************************************************************************
//* TIdRTCPSrcDescChunk Public methods *****************************************

constructor TIdRTCPSrcDescChunk.Create;
begin
  inherited Create;

  Self.ItemList := TObjectList.Create(true);
end;

destructor TIdRTCPSrcDescChunk.Destroy;
begin
  Self.ItemList.Free;

  inherited Destroy;
end;

procedure TIdRTCPSrcDescChunk.AddCanonicalName(Name: String);
begin
  Self.AddCanonicalHeader.Data := Name;
end;

function TIdRTCPSrcDescChunk.ItemCount: Integer;
begin
  Result := Self.ItemList.Count;
end;

procedure TIdRTCPSrcDescChunk.PrintOn(Dest: TStream);
var
  I: Integer;
begin
  WriteCardinal(Dest, Self.SyncSrcID);

  for I := 0 to Self.ItemCount - 1 do
    Self.Items[I].PrintOn(Dest);

  Self.PrintAlignmentPadding(Dest);
end;

procedure TIdRTCPSrcDescChunk.ReadFrom(Src: TStream);
var
  ID: Byte;
begin
  Self.SyncSrcID := ReadCardinal(Src);

  while Self.HasMoreItems(Src) do begin
    ID := PeekByte(Src);
    if (ID <> SDESEnd) then
      Self.AddItem(ID).ReadFrom(Src);
  end;

  Self.ReadAlignmentPadding(Src);
end;

function TIdRTCPSrcDescChunk.RealLength: Cardinal;
var
  I: Integer;
begin
  Result := 4;

  for I := 0 to Self.ItemCount - 1 do
    Result := Result + Self.Items[I].RealLength;
end;

//* TIdRTCPSrcDescChunk Private methods ****************************************

function TIdRTCPSrcDescChunk.AddCanonicalHeader: TIdSDESCanonicalName;
begin
  Result := Self.AddItem(SDESCName) as TIdSDESCanonicalName;
end;

function TIdRTCPSrcDescChunk.AddItem(ID: Byte): TIdSrcDescChunkItem;
begin
  Result := TIdSrcDescChunkItem.ItemType(ID).Create;
  try
    Self.ItemList.Add(Result);
  except
    if (Self.ItemList.IndexOf(Result) <> -1) then
      Self.ItemList.Remove(Result)
    else
      FreeAndNil(Result);

    raise;
  end;
end;

function TIdRTCPSrcDescChunk.GetItems(Index: Integer): TIdSrcDescChunkItem;
begin
  Result := Self.ItemList[Index] as TIdSrcDescChunkItem;
end;

function TIdRTCPSrcDescChunk.HasMoreItems(Src: TStream): Boolean;
begin
  Result := PeekByte(Src) <> 0;
end;

procedure TIdRTCPSrcDescChunk.PrintAlignmentPadding(Dest: TStream);
var
  I: Integer;
begin
  if (Self.RealLength mod 4 > 0) then
    for I := 1 to 4 - (Self.RealLength mod 4) do
      WriteByte(Dest, 0);
end;

procedure TIdRTCPSrcDescChunk.ReadAlignmentPadding(Src: TStream);
var
  I: Integer;
begin
  if (Self.RealLength mod 4 <> 0) then begin
    for I := 1 to 4 - (Self.RealLength mod 4) do
      ReadByte(Src);
  end;
end;

//******************************************************************************
//* TIdRTCPSourceDescription                                                   *
//******************************************************************************
//* TIdRTCPSourceDescription Public methods ************************************

constructor TIdRTCPSourceDescription.Create;
begin
  inherited Create;

  Self.ChunkList := TObjectList.Create(true);
end;

destructor TIdRTCPSourceDescription.Destroy;
begin
  Self.ChunkList.Free;

  inherited Destroy;
end;

function TIdRTCPSourceDescription.AddChunk: TIdRTCPSrcDescChunk;
begin
  if (Self.ChunkCount = High(Self.ChunkCount)) then begin
    Result := nil;
    Exit;
  end;

  Result := TIdRTCPSrcDescChunk.Create;
  try
    Self.ChunkList.Add(Result);
  except
    if (Self.ChunkList.IndexOf(Result) <> -1) then
      Self.ChunkList.Remove(Result)
    else
      FreeAndNil(Result);

    raise;
  end;
end;

function TIdRTCPSourceDescription.ChunkCount: TIdRTCPSourceCount;
begin
  Result := Self.ChunkList.Count;
end;

function TIdRTCPSourceDescription.GetAllSrcIDs: TCardinalDynArray;
var
  I, J: Integer;
begin
  SetLength(Result, Self.ChunkCount);

  J := Low(Result);
  for I := 0 to Self.ChunkCount - 1 do begin
    Result[J] := Self.Chunks[I].SyncSrcID;
    Inc(J);
  end;
end;

function TIdRTCPSourceDescription.IsSourceDescription: Boolean;
begin
  Result := true;
end;

procedure TIdRTCPSourceDescription.PrintOn(Dest: TStream);
var
  B: Byte;
  I: Integer;
begin
  B := Self.Version shl 6;
  if Self.HasPadding then
    B := B or $20;
  B := B or Self.ChunkCount;
  WriteByte(Dest, B);

  WriteByte(Dest, Self.PacketType);

  WriteWord(Dest, Self.Length);

  for I := 0 to Self.ChunkCount - 1 do
    Self.Chunks[I].PrintOn(Dest);

  if Self.HasPadding then
    Self.PrintPadding(Dest);
end;

procedure TIdRTCPSourceDescription.ReadFrom(Src: TStream);
var
  B:         Byte;
  I:         Integer;
  NumChunks: TIdFiveBitInt;
begin
  B := ReadByte(Src);
  Self.Version    := (B and $C0) shr 6;
  Self.HasPadding := (B and $20) <> 0;
  NumChunks := B and $1F;

  Self.AssertPacketType(ReadByte(Src));
  Self.Length := ReadWord(Src);

  for I := 1 to NumChunks do
    Self.ReadChunk(Src);
end;

function TIdRTCPSourceDescription.RealLength: Word;
var
  I: Integer;
begin
  Result := 4;
  for I := 0 to Self.ChunkCount - 1 do
    Result := Result + Self.Chunks[I].RealLength;
end;

//* TIdRTCPSourceDescription Protected methods *********************************

function TIdRTCPSourceDescription.GetPacketType: Cardinal;
begin
  Result := RTCPSourceDescription;
end;

function TIdRTCPSourceDescription.GetSyncSrcID: Cardinal;
begin
  if (Self.ChunkCount = 0) then
    Result := 0
  else
    Result := Self.Chunks[0].SyncSrcID;
end;

procedure TIdRTCPSourceDescription.SetSyncSrcID(const Value: Cardinal);
begin
  if (Self.ChunkCount = 0) then
    Self.AddChunk;

  Self.Chunks[0].SyncSrcID := Value;
end;

//* TIdRTCPSourceDescription Private methods ***********************************

function TIdRTCPSourceDescription.GetChunks(Index: Integer): TIdRTCPSrcDescChunk;
begin
  Result := Self.ChunkList[Index] as TIdRTCPSrcDescChunk;
end;

procedure TIdRTCPSourceDescription.ReadChunk(Src: TStream);
begin
  Self.AddChunk.ReadFrom(Src);
end;

//******************************************************************************
//* TIdRTCPBye                                                                 *
//******************************************************************************
//* TIdRTCPBye Public methods **************************************************

constructor TIdRTCPBye.Create;
begin
  inherited Create;

  Self.SourceCount := 1;
end;

function TIdRTCPBye.GetAllSrcIDs: TCardinalDynArray;
var
  I, J: Integer;
begin
  SetLength(Result, Self.SourceCount);

  J := Low(Result);
  for I := 0 to Self.SourceCount - 1 do begin
    Result[J] := Self.Sources[I];
    Inc(J);
  end;
end;

function TIdRTCPBye.IsBye: Boolean;
begin
  Result := true;
end;

procedure TIdRTCPBye.PrintOn(Dest: TStream);
var
  B: Byte;
  I: Integer;
begin
  B := Self.Version shl 6;
  B := B or Self.SourceCount;
  if Self.HasPadding then B := B or $20;
  WriteByte(Dest, B);
  WriteByte(Dest, Self.GetPacketType);
  WriteWord(Dest, Self.Length);

  for I := 0 to Self.SourceCount - 1 do
    WriteCardinal(Dest, Self.Sources[I]);

  if (Self.ReasonLength > 0) then begin
    WriteByte(Dest, Self.ReasonLength);
    WriteString(Dest, Self.Reason);
  end;

  if Self.HasPadding then
    Self.PrintPadding(Dest);
end;

procedure TIdRTCPBye.ReadFrom(Src: TStream);
var
  B: Byte;
  I: Integer;
begin
  B := ReadByte(Src);
  Self.Version     := B and $C0 shr 6;
  Self.HasPadding  := (B and $20) <> 0;
  Self.SourceCount := B and $1F;

  Self.AssertPacketType(ReadByte(Src));

  Self.Length := ReadWord(Src);

  for I := 0 to Self.SourceCount - 1 do
    Self.Sources[I] := ReadCardinal(Src);

  if Self.StreamHasReason then begin
    Self.ReasonLength := ReadByte(Src);

    Self.Reason := ReadString(Src, Self.ReasonLength);
    Self.ReadReasonPadding(Src);
  end;
end;

function TIdRTCPBye.RealLength: Word;
begin
  Result := 4 + Self.SourceCount*4;

  if (Self.Reason <> '') then
    Result := Result + SizeOf(Self.ReasonLength) + System.Length(Self.Reason);
end;

//* TIdRTCPBye Protected methods ***********************************************

function TIdRTCPBye.GetPacketType: Cardinal;
begin
  Result := RTCPGoodbye;
end;

function TIdRTCPBye.GetSyncSrcID: Cardinal;
begin
  Result := Self.Sources[0];
end;

procedure TIdRTCPBye.SetSyncSrcID(const Value: Cardinal);
begin
  Self.Sources[0] := Value;
end;

//* TIdRTCPBye Private methods *************************************************

function TIdRTCPBye.GetSourceCount: TIdRTCPSourceCount;
begin
  Result := System.Length(fSources);
end;

function TIdRTCPBye.GetSource(Index: TIdRTCPSourceCount): Cardinal;
begin
  Result := fSources[Index];
end;

procedure TIdRTCPBye.ReadReasonPadding(Src: TStream);
var
  Mod4Length: Byte;
begin
  // Self.ReasonLength consumes 1 byte; ergo, to align the Reason on a 32-bit
  // word boundary requires that you pad on one less than ReasonLength.
  Mod4Length := (Self.ReasonLength + 1) mod 4;

  if (Mod4Length <> 0) then
    ReadString(Src, 4 - Mod4Length);
end;

procedure TIdRTCPBye.SetReason(const Value: String);
begin
  fReason := Value;
  Self.ReasonLength := System.Length(Value);
end;

procedure TIdRTCPBye.SetSource(Index: TIdRTCPSourceCount;
                                     const Value: Cardinal);
begin
  Self.SourceCount := Max(Self.SourceCount, Index + 1);
  fSources[Index] := Value;
end;

procedure TIdRTCPBye.SetSourceCount(const Value: TIdRTCPSourceCount);
begin
  SetLength(fSources, Value);
end;

function TIdRTCPBye.StreamHasReason: Boolean;
begin
  // Hackish. Length is the length of this RTCP packet in 32-bit words minus
  // one. SourceCount tells us how many SSRCS this packet contains, and SSRCs
  // are 32-bit words. Bye packets have one 32-bit word other than the SSRCs.
  // Therefore if Self.Length > Self.SourceCount we must have a Reason field.
  Result := Self.Length > Self.SourceCount;
end;

//******************************************************************************
//* TIdRTCPApplicationDefined                                                  *
//******************************************************************************
//* TIdRTCPApplicationDefined Public methods ***********************************

constructor TIdRTCPApplicationDefined.Create;
begin
  inherited Create;

  Self.Name := #0#0#0#0;
  Self.Length := 2;
end;

procedure TIdRTCPApplicationDefined.PrintOn(Dest: TStream);
var
  B: Byte;
  I: Integer;
begin
  B := Self.Version shl 6;
  if Self.HasPadding then B := B or $20;
  WriteByte(Dest, B);
  WriteByte(Dest, Self.GetPacketType);
  WriteWord(Dest, Self.Length);

  WriteCardinal(Dest, Self.SyncSrcID);

  WriteString(Dest, Self.Name);
  for I := 1 to 4 - System.Length(Name) do
    WriteByte(Dest, 0);

  WriteString(Dest, Self.Data);

  if Self.HasPadding then
    Self.PrintPadding(Dest);
end;

procedure TIdRTCPApplicationDefined.ReadFrom(Src: TStream);
const
  // The size of the set headers of an Application-Defined RTCP packet
  // IN 32-BIT WORDS - cf. RFC 3550, section 6.7
  DataOffset = 3;
var
  B:    Byte;
  Name: array[0..3] of Char;
begin
  B := ReadByte(Src);
  Self.Version    := B and $C0 shr 6;
  Self.HasPadding := (B and $20) <> 0;

  Self.AssertPacketType(ReadByte(Src));

  Self.Length := ReadWord(Src);
  Self.SyncSrcID := ReadCardinal(Src);

  Src.Read(Name, System.Length(Name));
  Self.Name := Name;

  if (Self.Length > DataOffset) then
    Self.Data := ReadString(Src, (Self.Length - DataOffset + 1)*4);
end;

function TIdRTCPApplicationDefined.RealLength: Word;
begin
  Result := 8
            + Self.LengthOfName
            + System.Length(Self.Data);
end;

//* TIdRTCPApplicationDefined Protected methods ********************************

function TIdRTCPApplicationDefined.GetPacketType: Cardinal;
begin
  Result := RTCPApplicationDefined;
end;

//* TIdRTCPApplicationDefined Private methods **********************************

function TIdRTCPApplicationDefined.LengthOfName: Byte;
begin
  Result := 4;
end;

procedure TIdRTCPApplicationDefined.SetData(const Value: String);
var
  Len: Integer;
begin
  fData := Value;

  Len := System.Length(fData);

  if (Len mod 4 <> 0) then
    while System.Length(fData) < 4*((Len div 4) + 1) do
      fData := fData + #0;
end;

procedure TIdRTCPApplicationDefined.SetName(const Value: String);
begin
  if (System.Length(Value) > 4) then
    fName := Copy(Value, 1, 4)
  else
    fName := Value;
end;

//******************************************************************************
//* TIdCompoundRTCPPacket                                                      *
//******************************************************************************
//* TIdCompoundRTCPPacket Public methods ***************************************

constructor TIdCompoundRTCPPacket.Create;
begin
  inherited Create;

  Self.Packets := TObjectList.Create(true);
end;

destructor TIdCompoundRTCPPacket.Destroy;
begin
  Self.Packets.Free;

  inherited Destroy;
end;

function TIdCompoundRTCPPacket.AddApplicationDefined: TIdRTCPApplicationDefined;
begin
  Result := Self.Add(TIdRTCPApplicationDefined) as TIdRTCPApplicationDefined;
end;

function TIdCompoundRTCPPacket.AddBye: TIdRTCPBye;
begin
  Result := Self.Add(TIdRTCPBye) as TIdRTCPBye;
end;

function TIdCompoundRTCPPacket.AddReceiverReport: TIdRTCPReceiverReport;
begin
  Result := Self.Add(TIdRTCPReceiverReport) as TIdRTCPReceiverReport;
end;

function TIdCompoundRTCPPacket.AddSenderReport: TIdRTCPSenderReport;
begin
  Result := Self.Add(TIdRTCPSenderReport) as TIdRTCPSenderReport;
end;

function TIdCompoundRTCPPacket.AddSourceDescription: TIdRTCPSourceDescription;
begin
  Result := Self.Add(TIdRTCPSourceDescription) as TIdRTCPSourceDescription;
end;

function TIdCompoundRTCPPacket.FirstPacket: TIdRTCPPacket;
begin
  if (Self.PacketCount > 0) then
    Result := Self.PacketAt(0)
  else
    Result := nil;
end;

function TIdCompoundRTCPPacket.HasBye: Boolean;
var
  I: Cardinal;
begin
  Result := false;

  I := 0;
  while (I < Self.PacketCount) and not Result do begin
    if Self.PacketAt(I).IsBye then
      Result := true;
    Inc(I);
  end;
end;

function TIdCompoundRTCPPacket.HasSourceDescription: Boolean;
var
  I: Cardinal;
begin
  Result := false;

  I := 0;
  while (I < Self.PacketCount) and not Result do begin
    if Self.PacketAt(I).IsSourceDescription then
      Result := true;
    Inc(I);
  end;
end;

function TIdCompoundRTCPPacket.IsRTCP: Boolean;
begin
  Result := true;
end;

function TIdCompoundRTCPPacket.IsRTP: Boolean;
begin
  Result := false;
end;

function TIdCompoundRTCPPacket.IsValid: Boolean;
begin
  Result := inherited IsValid
        and (Self.PacketCount > 0)
        and (Self.FirstPacket.IsSenderReport or Self.FirstPacket.IsReceiverReport)
        and not Self.FirstPacket.HasPadding;
end;

function TIdCompoundRTCPPacket.PacketAt(Index: Cardinal): TIdRTCPPacket;
begin
  Result := Self.Packets[Index] as TIdRTCPPacket;
end;

function TIdCompoundRTCPPacket.PacketCount: Cardinal;
begin
  Result := Self.Packets.Count;
end;

procedure TIdCompoundRTCPPacket.PrepareForTransmission(Session: TIdRTPSession);
var
  I: Cardinal;
begin
  if (Self.PacketCount > 0) then
    for I := 0 to Self.PacketCount - 1 do
      Self.PacketAt(I).PrepareForTransmission(Session);
end;

procedure TIdCompoundRTCPPacket.PrintOn(Dest: TStream);
var
  I: Integer;
begin
  if (Self.PacketCount > 0) then
    for I := 0 to Self.PacketCount - 1 do
      Self.PacketAt(I).PrintOn(Dest);
end;

procedure TIdCompoundRTCPPacket.ReadFrom(Src: TStream);
var
  Peek: Word;
begin
  Peek := PeekWord(Src);
  while (Peek <> 0) do begin
    Self.Add(TIdRTCPPacket.RTCPType(Peek and $00ff)).ReadFrom(Src);
    Peek := PeekWord(Src);
  end;
end;

function TIdCompoundRTCPPacket.RealLength: Word;
begin
  Result := Self.Length * SizeOf(Cardinal);
end;

//* TIdCompoundRTCPPacket Protected methods ************************************

function TIdCompoundRTCPPacket.GetPacketType: Cardinal;
begin
  if (Self.PacketCount > 0) then
    Result := Self.PacketAt(0).PacketType
  else
    Result := 0;
end;

//* TIdCompoundRTCPPacket Private methods **************************************

function TIdCompoundRTCPPacket.Add(PacketType: TIdRTCPPacketClass): TIdRTCPPacket;
begin
  Result := PacketType.Create;
  try
    Self.Packets.Add(Result)
  except
    if (Self.Packets.IndexOf(Result) <> -1) then
      Self.Packets.Remove(Result)
    else
      Result.Free;
    raise;
  end;
end;

//******************************************************************************
//* TIdRTPMember                                                               *
//******************************************************************************
//* TIdRTPMember Public methods ************************************************

constructor TIdRTPMember.Create;
begin
  inherited Create;

  Self.ControlAddress           := '';
  Self.ControlPort              := 0;
  Self.HasLeftSession           := false;
  Self.IsSender                 := false;
  Self.LocalAddress             := false;
  Self.MaxDropout               := Self.DefaultMaxDropout;
  Self.MaxMisOrder              := Self.DefaultMaxMisOrder;
  Self.MinimumSequentialPackets := Self.DefaultMinimumSequentialPackets;
  Self.Probation                := Self.MinimumSequentialPackets;
  Self.SentData                 := false;
  Self.SentControl              := false;
  Self.SourceAddress            := '';
  Self.SourcePort               := 0;
end;

function TIdRTPMember.DelaySinceLastSenderReport: Cardinal;
begin
  // Return the length of time, expressed in units of 1/65536 seconds,
  // since we last received a Sender Report from the source.

  if (Self.LastSenderReportReceiptTime = 0) then
    Result := 0
  else
   Result := Trunc(SecondSpan(Now, Self.LastSenderReportReceiptTime)*65536);
end;

procedure TIdRTPMember.InitSequence(Data: TIdRTPPacket);
begin
  Assert(Self.SyncSrcID = Data.SyncSrcID,
         'Member received an RTP packet not meant for it');

  Self.BaseSeqNo    := Data.SequenceNo;
  Self.BadSeqNo     := Self.SequenceNumberRange + 1;
  Self.HighestSeqNo := Data.SequenceNo;

  // Data is the very first packet from the newly-validated source
  Self.ReceivedPackets := 1;
end;

function TIdRTPMember.IsInSequence(Data: TIdRTPPacket): Boolean;
begin
  Result := Data.SequenceNo = Self.HighestSeqNo + 1;
end;

function TIdRTPMember.IsUnderProbation: Boolean;
begin
  Result := Self.Probation > 0;
end;

function TIdRTPMember.LastSenderReport: Cardinal;
var
  NTP: TIdNTPTimestamp;
begin
  // This returns the middle 32 bits out of an NTP timestamp of the last
  // time we received a Sender Report.

  if (Self.LastSenderReportReceiptTime = 0) then begin
    Result := 0;
    Exit;
  end;

  NTP := DateTimeToNTPTimestamp(Self.LastSenderReportReceiptTime);

  Result := ((NTP.IntegerPart and $0000ffff) shl 16)
        or ((NTP.FractionalPart and $ffff0000) shr 16);
end;

function TIdRTPMember.PacketLossCount: Cardinal;
const
  MaxPacketLoss = $7fffff;
  MinPacketLoss = -$800000;
var
  Count: Int64;
begin
  // Return a 24-bit signed value of the number of packets lost in the last
  // report interval.

  Count := Int64(Self.ExpectedPacketCount) - Self.ReceivedPackets;

  if (Count > MaxPacketLoss) then
    Count := MaxPacketLoss
  else if (Count < MinPacketLoss) then
    Count := MinPacketLoss;

  // Translate into 24-bit signed value
  if (Count < 0) then
    Count := TwosComplement(Count);

  Result := Count and $ffffff;
end;

function TIdRTPMember.PacketLossFraction: Byte;
var
  ExpectedInterval: Int64;
  LostInterval:     Int64;
  ReceivedInterval: Int64;
begin
  // Return an 8-bit fixed-point fraction of the number of packets lost
  // in the last reporting interval.

  ExpectedInterval := Self.ExpectedPacketCount - Self.ExpectedPrior;
  ReceivedInterval := Self.ReceivedPackets - Self.ReceivedPrior;

  LostInterval := ExpectedInterval - ReceivedInterval;

  if (ExpectedInterval = 0) or (LostInterval < 0) then
    Result := 0
  else
    Result := ((LostInterval shl 8) div ExpectedInterval) and $ff;
end;

function TIdRTPMember.SequenceNumberRange: Cardinal;
begin
  Result := High(Self.BaseSeqNo) + 1; // 1 shl 16
end;

function TIdRTPMember.UpdateStatistics(Data: TIdRTPPacket; CurrentTime: TIdRTPTimestamp): Boolean;
begin
  Result := Self.UpdateSequenceNo(Data);
  Self.UpdateJitter(Data, CurrentTime);
  Self.UpdatePrior;

  Self.LastRTPReceiptTime := Now;
end;

procedure TIdRTPMember.UpdateStatistics(Stats: TIdRTCPPacket);
begin
  if Stats.IsSenderReport then
    Self.LastSenderReportReceiptTime := Now;

  Self.LastRTCPReceiptTime := Now;
end;

//* TIdRTPMember Private methods ***********************************************

function TIdRTPMember.DefaultMaxDropout: Cardinal;
begin
  // This tells us how big a gap in the sequence numbers we will
  // accept before invalidating the source.
  Result := 3000;
end;

function TIdRTPMember.DefaultMaxMisOrder: Word;
begin
  // We accept packets as valid if their sequence numbers are no more
  // than MaxMisOrder behind HighestSeqNo.
  Result := 100;
end;

function TIdRTPMember.DefaultMinimumSequentialPackets: Cardinal;
begin
  // This tells us how many packets we must receive, _in_order_, before
  // we validate a source.
  Result := 2;
end;

function TIdRTPMember.ExpectedPacketCount: Cardinal;
var
  RealMax: Cardinal;
begin
  RealMax := (Self.Cycles * Self.SequenceNumberRange)
           + Self.HighestSeqNo;

  Result := RealMax - Self.BaseSeqNo + 1;
end;

procedure TIdRTPMember.UpdateJitter(Data: TIdRTPPacket; CurrentTime: Cardinal);
var
  Delta:   Int64;
  Transit: Int64;
begin
  Transit := Int64(CurrentTime) - Data.Timestamp;
  Delta := Abs(Transit - Self.PreviousPacketTransit);
  Self.PreviousPacketTransit := Transit;

  Self.Jitter := (Int64(Self.Jitter) + Delta - ((Self.Jitter + 8) shr 4))
                 and $ffffffff;
end;

procedure TIdRTPMember.UpdatePrior;
begin
  Self.ExpectedPrior := Self.ExpectedPacketCount;
  Self.ReceivedPrior := Self.ReceivedPackets;
end;

function TIdRTPMember.UpdateSequenceNo(Data: TIdRTPPacket): Boolean;
var
  Delta: Cardinal;
begin
  if (Data.SequenceNo < Self.HighestSeqNo) then
    Delta := High(Data.SequenceNo) - (Self.HighestSeqNo - Data.SequenceNo)
  else
    Delta := Data.SequenceNo - Self.HighestSeqNo;

  if Self.IsUnderProbation then begin
    if Self.IsInSequence(Data) then begin
      Self.Probation := Self.Probation - 1;
      Self.HighestSeqNo  := Data.SequenceNo;

      if not Self.IsUnderProbation then begin
        Self.InitSequence(Data);
        Result := true;
        Exit;
      end;
    end
    else begin
      // First received packet - one down, Self.MinimumSequentialPackets - 1
      Self.Probation := Self.MinimumSequentialPackets - 1;
      Self.HighestSeqNo  := Data.SequenceNo;
    end;
    Result := false;
    Exit;
  end
  else if (Delta < Self.MaxDropout) then begin
    // In order, with permissible gap
    if (Data.SequenceNo < Self.HighestSeqNo) then begin
      // Sequence number wrapped - count another 64k cycle
      Self.Cycles := Self.Cycles + 1;//Self.SequenceNumberRange;
    end;
    Self.HighestSeqNo := Data.SequenceNo;
  end
  else if (Delta < Self.SequenceNumberRange - Self.MaxMisOrder) then begin
    // The sequence made a very large jump
    if (Data.SequenceNo = Self.BadSeqNo) then begin
      // Two sequential packets - assume the other side restarted without
      // telling us so just re-sync (i.e., pretend this was the first
      // packet).
      Self.InitSequence(Data);
    end
    else begin
      Self.BadSeqNo := (Data.SequenceNo + 1) and (Self.SequenceNumberRange - 1);
      Result := false;
      Exit;
    end;
  end
  else begin
    // duplicate or re-ordered packet
  end;
  Self.ReceivedPackets := Self.ReceivedPackets + 1;
  Result := true;
end;

//******************************************************************************
//* TIdRTPMemberTable                                                          *
//******************************************************************************
//* TIdRTPMemberTable Public methods *******************************************

constructor TIdRTPMemberTable.Create;
begin
  inherited Create;

  Self.List := TObjectList.Create(true);
end;

destructor TIdRTPMemberTable.Destroy;
begin
  Self.List.Free;

  inherited Destroy;
end;

function TIdRTPMemberTable.Add(SSRC: Cardinal): TIdRTPMember;
begin
  if Self.Contains(SSRC) then begin
    Result := Self.Find(SSRC);
    Exit;
  end;

  Result := TIdRTPMember.Create;
  try
    Self.List.Add(Result);

    Result.ControlAddress := '';
    Result.ControlPort    := 0;
    Result.SourceAddress  := '';
    Result.SourcePort     := 0;
    Result.SyncSrcID      := SSRC;
  except
    if (Self.List.IndexOf(Result) <> -1) then
      Self.List.Remove(Result)
    else
      FreeAndNil(Result);

    raise;
  end;
end;

function TIdRTPMemberTable.AddSender(SSRC: Cardinal): TIdRTPMember;
begin
  Result := Self.Add(SSRC);
  Result.IsSender := true;
end;

procedure TIdRTPMemberTable.AdjustTransmissionTime(PreviousMemberCount: Cardinal;
                                                   var NextTransmissionTime: TDateTime;
                                                   var PreviousTransmissionTime: TDateTime);
var
  Timestamp: TDateTime;
begin
  Timestamp := Now;

  NextTransmissionTime := Timestamp
           + (Self.Count/PreviousMemberCount) * (NextTransmissionTime - Timestamp);

  PreviousTransmissionTime := Timestamp
           - (Self.Count/PreviousMemberCount) * (Timestamp - PreviousTransmissionTime);
end;

function TIdRTPMemberTable.Contains(SSRC: Cardinal): Boolean;
begin
  Result := Assigned(Self.Find(SSRC));
end;

function TIdRTPMemberTable.Count: Cardinal;
begin
  Result := Self.List.Count;
end;

function TIdRTPMemberTable.DeterministicSendInterval(ForSender: Boolean;
                                                     Session: TIdRTPSession): TDateTime;
var
  MinInterval:         TDateTime;
  N:                   Cardinal;
  NewMaxRTCPBandwidth: Cardinal;
begin
  MinInterval := Session.MinimumRTCPSendInterval;

  if (Session.NoControlSent) then
    MinInterval := MinInterval / 2;

  NewMaxRTCPBandwidth := Session.MaxRTCPBandwidth;
  N := Self.Count;
  if (Self.SenderCount <= Round(Self.Count * Session.SenderBandwidthFraction)) then begin
    if ForSender then begin
      NewMaxRTCPBandwidth := Round(NewMaxRTCPBandwidth * Session.SenderBandwidthFraction);
      N := Self.SenderCount;
    end
    else begin
      NewMaxRTCPBandwidth := Round(NewMaxRTCPBandwidth * Session.ReceiverBandwidthFraction);
      N := Self.ReceiverCount;
    end;
  end;

  if (NewMaxRTCPBandwidth > 0) then begin
    Result := OneSecond * Session.AvgRTCPSize * N / NewMaxRTCPBandwidth;

    if (Result < MinInterval) then
      Result := MinInterval;
  end
  else
    Result := MinInterval;

  Session.MaxRTCPBandwidth := NewMaxRTCPBandwidth;
end;

function TIdRTPMemberTable.Find(SSRC: Cardinal): TIdRTPMember;
var
  I: Cardinal;
begin
  Result := nil;
  I := 0;

  while (I < Self.Count) and not Assigned(Result) do
    if (Self.MemberAt(I).SyncSrcID = SSRC) then
      Result := Self.MemberAt(I)
    else
      Inc(I);
end;

function TIdRTPMemberTable.MemberAt(Index: Cardinal): TIdRTPMember;
begin
  // TODO: This will blow up when Index > High(Integer)
  Result := Self.List[Index] as TIdRTPMember;
end;

function TIdRTPMemberTable.MemberTimeout(Session: TIdRTPSession): TDateTime;
begin
  Result := Now
          - Session.MissedReportTolerance * Self.DeterministicSendInterval(false, Session);
end;

function TIdRTPMemberTable.ReceiverCount: Cardinal;
begin
  Result := Self.Count - Self.SenderCount;
end;

procedure TIdRTPMemberTable.Remove(SSRC: Cardinal);
begin
  Self.List.Remove(Self.Find(SSRC));
end;

procedure TIdRTPMemberTable.RemoveAll;
begin
  Self.List.Clear;
end;

procedure TIdRTPMemberTable.RemoveSources(Bye: TIdRTCPBye);
var
  I:   Cardinal;
  IDs: TCardinalDynArray;
begin
  IDs := Bye.GetAllSrcIDs;

  for I := Low(IDs) to High(IDs) do
    Self.Remove(IDs[I]);
end;

procedure TIdRTPMemberTable.RemoveTimedOutMembersExceptFor(CutoffTime: TDateTime;
                                                           SessionSSRC: Cardinal);
var
  I: Cardinal;
begin
  I := 0;
  while (I < Self.Count) do begin
    if (Self.MemberAt(I).SyncSrcID <> SessionSSRC)
      and (Self.MemberAt(I).LastRTCPReceiptTime < CutoffTime) then
      Self.Remove(Self.MemberAt(I).SyncSrcID)
    else
      Inc(I)
  end;
end;

procedure TIdRTPMemberTable.RemoveTimedOutSenders(CutoffTime: TDateTime);
var
  I: Cardinal;
begin
  I := 0;
  while (I < Self.Count) do begin
    if Self.MemberAt(I).IsSender
      and (Self.MemberAt(I).LastRTCPReceiptTime < CutoffTime) then
      Self.Remove(Self.MemberAt(I).SyncSrcID)
    else
      Inc(I);
  end;
end;

function TIdRTPMemberTable.SenderCount: Cardinal;
var
  I: Cardinal;
begin
  Result := 0;
  if (Self.Count > 0) then
    for I := 0 to Self.Count - 1 do
      if Self.MemberAt(I).IsSender then
        Inc(Result);

end;

function TIdRTPMemberTable.SenderTimeout(Session: TIdRTPSession): TDateTime;
begin
  Result := Now - 2*Self.SendInterval(Session);
end;

function TIdRTPMemberTable.SendInterval(Session: TIdRTPSession): TDateTime;
begin
  // Return the number of milliseconds until we must send the next RTCP
  // (i.e., SR/RR) packet to the members of this session.

  Result := Self.DeterministicSendInterval(Session.IsSender, Session)
          * Self.RandomTimeFactor
          / Self.CompensationFactor;
end;

procedure TIdRTPMemberTable.SetControlBinding(SSRC: Cardinal;
                                              Binding: TIdSocketHandle);
var
  ID: TCardinalDynArray;
begin
  SetLength(ID, 1);
  ID[0] := SSRC;
  Self.SetControlBindings(ID, Binding);
end;

procedure TIdRTPMemberTable.SetControlBindings(SSRCs: TCardinalDynArray;
                                               Binding: TIdSocketHandle);
var
  I:         Cardinal;
  NewMember: TIdRTPMember;
begin
  for I := Low(SSRCs) to High(SSRCs) do begin
    NewMember := Self.Find(SSRCs[I]);
    if not Assigned(NewMember) then
      NewMember := Self.Add(SSRCs[I]);

    if not NewMember.SentControl then begin
      NewMember.ControlAddress := Binding.PeerIP;
      NewMember.ControlPort    := Binding.PeerPort;
      NewMember.SentControl    := true;
    end;
  end;
end;

procedure TIdRTPMemberTable.SetDataBinding(SSRC: Cardinal;
                                           Binding: TIdSocketHandle);
var
  NewMember: TIdRTPMember;
begin
  NewMember := Self.Find(SSRC);
  if not Assigned(NewMember) then
    NewMember := Self.AddSender(SSRC)
  else
    NewMember.IsSender := true;

  if not NewMember.SentControl then begin
    NewMember.SourceAddress := Binding.PeerIP;
    NewMember.SourcePort    := Binding.PeerPort;
    NewMember.SentControl   := true;
  end;
end;

//* TIdRTPMemberTable Private methods ******************************************

function TIdRTPMemberTable.CompensationFactor: Double;
begin
  // cf RFC 3550, section 6.3.1:
  // The resulting value of T is divided by e-3/2=1.21828 to compensate
  // for the fact that the timer reconsideration algorithm converges to
  // a value of the RTCP bandwidth below the intended average.

  Result := Exp(1) - 1.5;
end;

function TIdRTPMemberTable.RandomTimeFactor: Double;
begin
  // We want a factor in the range [0.5, 1.5]
  Result := TIdRandomNumber.NextDouble + 0.5;
end;

//******************************************************************************
//* TIdRTPSenderTable                                                          *
//******************************************************************************
//* TIdRTPSenderTable Public methods *******************************************

constructor TIdRTPSenderTable.Create(MemberTable: TIdRTPMemberTable);
begin
  inherited Create;

  Self.Members := MemberTable;
end;

function  TIdRTPSenderTable.Add(SSRC: Cardinal): TIdRTPMember;
begin
  Result := Self.Members.AddSender(SSRC);
end;

function TIdRTPSenderTable.Contains(SSRC: Cardinal): Boolean;
begin
  Result := Self.Members.Contains(SSRC);

  if Result then
    Result := Result and Self.Members.Find(SSRC).IsSender;
end;

function TIdRTPSenderTable.Count: Cardinal;
var
  I: Cardinal;
begin
  //  In Smalltalk:
  // ^(self members select: [ :each | each isSender ]) size
  Result := 0;

  if (Self.Members.Count > 0) then
    for I := 0 to Self.Members.Count - 1 do
      if Self.Members.MemberAt(I).IsSender then
        Inc(Result);
end;

function TIdRTPSenderTable.Find(SSRC: Cardinal): TIdRTPMember;
var
  I: Cardinal;
begin
  // in Smalltalk:
  // ^self members
  //         detect: [ :each | each isSender and: [ each ssrc = ssrc ]]
  //         ifNone: [ nil ]
  Result := nil;

  if (Self.Members.Count > 0) then
    for I := 0 to Self.Members.Count - 1 do
      if Self.Members.MemberAt(I).IsSender
        and (Self.Members.MemberAt(I).SyncSrcID = SSRC) then begin
        Result := Self.Members.MemberAt(I);
        Break;
      end;
end;

function TIdRTPSenderTable.MemberAt(Index: Cardinal): TIdRTPMember;
var
  I:           Cardinal;
  MemberIndex: Cardinal;
begin
  Result := nil;

  if (Self.Members.Count > 0) then begin
    MemberIndex := 0;
    I           := 0;

    // Loop invariant: MemberIndex <= I
    while (I < Self.Members.Count) and not Assigned(Result) do begin
      if Self.Members.MemberAt(I).IsSender then begin
        if (MemberIndex = Index) then
          Result := Self.Members.MemberAt(I)
        else
          Inc(MemberIndex);
      end;

      Inc(I);
    end;
  end;
end;

procedure TIdRTPSenderTable.Remove(SSRC: Cardinal);
begin
  Self.Members.Remove(SSRC);
end;

procedure TIdRTPSenderTable.RemoveAll;
var
  I: Cardinal;
begin
  I := 0;
  if (Self.Members.Count > 0) then
    while (I < Self.Members.Count) do
     if Self.Members.MemberAt(I).IsSender then
       Self.Members.Remove(Self.Members.MemberAt(I).SyncSrcID)
     else
       Inc(I);
end;

//******************************************************************************
//* TIdRTPSession                                                              *
//******************************************************************************
//* TIdRTPSession Public methods ***********************************************

constructor TIdRTPSession.Create(Agent: TIdAbstractRTPPeer;
                                 Profile: TIdRTPProfile);
begin
  inherited Create;

  Self.Agent          := Agent;
  Self.fNoControlSent := true;
  Self.NoDataSent     := true;
  Self.Profile        := Profile;

  Self.MemberLock := TCriticalSection.Create;
  Self.Members    := TIdRTPMemberTable.Create;
  Self.Senders    := TIdRTPSenderTable.Create(Self.Members);

  Self.TransmissionLock := TCriticalSection.Create;
  Self.Timer            := TIdRTPTimerQueue.Create;

  Self.AssumedMTU            := Self.DefaultAssumedMTU;
  Self.MissedReportTolerance := Self.DefaultMissedReportTolerance;

  Self.Initialize;
end;

destructor TIdRTPSession.Destroy;
begin
  Self.Timer.Free;
  Self.TransmissionLock.Free;
  Self.Senders.Free;
  Self.Members.Free;
  Self.MemberLock.Free;

  inherited Destroy;
end;

function TIdRTPSession.AcceptableSSRC(SSRC: Cardinal): Boolean;
begin
  Result := (SSRC <> 0) and not Self.IsMember(SSRC);
end;

function TIdRTPSession.AddMember(SSRC: Cardinal): TIdRTPMember;
begin
  Self.MemberLock.Acquire;
  try
    Result := Self.Members.Add(SSRC);
  finally
    Self.MemberLock.Release;
  end;
end;

function TIdRTPSession.AddSender(SSRC: Cardinal): TIdRTPMember;
begin
  Self.Members.Add(SSRC);
  Result := Self.Senders.Add(SSRC);
end;

function TIdRTPSession.CreateNextReport: TIdCompoundRTCPPacket;
begin
  // Either an RR or SR, plus an SDES
  Result := TIdCompoundRTCPPacket.Create;
  try
    Self.AddReports(Result);
    Self.AddSourceDesc(Result);
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function TIdRTPSession.DeterministicSendInterval(ForSender: Boolean): TDateTime;
begin
  Result := Self.Members.DeterministicSendInterval(ForSender, Self);
end;

procedure TIdRTPSession.Initialize;
begin
  Self.SequenceNo    := TIdRandomNumber.NextCardinal(High(Self.SequenceNo));
  Self.BaseTimestamp := TIdRandomNumber.NextCardinal;
  Self.BaseTime      := Now;

  Self.Members.RemoveAll;

  Self.SetSyncSrcId(Self.NewSSRC);
  Self.AddMember(Self.SyncSrcID).LocalAddress := true;
  Self.SenderBandwidthFraction   := Self.DefaultSenderBandwidthFraction;
  Self.ReceiverBandwidthFraction := Self.DefaultReceiverBandwidthFraction;

  Self.fPreviousMemberCount     := 1;
  Self.PreviousTransmissionTime := 0;
  Self.fAvgRTCPSize             := Self.DefaultNoControlSentAvgRTCPSize;
end;

function TIdRTPSession.IsMember(SSRC: Cardinal): Boolean;
begin
  Self.MemberLock.Acquire;
  try
    Result := Self.Members.Contains(SSRC);
  finally
    Self.MemberLock.Release;
  end;
end;

function TIdRTPSession.IsSender: Boolean;
begin
  Result := IsSender(Self.SyncSrcID);
//  Result := Self.Members.Find(Self.SyncSrcID).IsSender;
end;

function TIdRTPSession.IsSender(SSRC: Cardinal): Boolean;
begin
  Result := Self.Senders.Contains(SSRC);
end;

procedure TIdRTPSession.LeaveSession(Reason: String = '');
var
  Bye: TIdRTCPBye;
begin
  // TODO: RFC 3550 section 6.3.7 - if a session contains more than 50 members
  // then there's a low-bandwidth algorithm for sending BYEs that prevents a
  // "storm".
  Bye := TIdRTCPBye.Create;
  try
    Self.SendControl(Bye);
  finally
    Bye.Free;
  end;
end;

function TIdRTPSession.LockMembers: TIdRTPMemberTable;
begin
  Self.MemberLock.Acquire;
  Result := Self.Members;
end;

function TIdRTPSession.Member(SSRC: Cardinal): TIdRTPMember;
begin
  Self.MemberLock.Acquire;
  try
    Result := Self.Members.Find(SSRC);
  finally
    Self.MemberLock.Release;
  end;
end;

function TIdRTPSession.MemberCount: Cardinal;
begin
  Self.MemberLock.Acquire;
  try
    Result := Self.Members.Count;
  finally
    Self.MemberLock.Release;
  end;
end;

function TIdRTPSession.MinimumRTCPSendInterval: TDateTime;
begin
  Result := 5*OneSecond;
end;

function TIdRTPSession.NewSSRC: Cardinal;
var
  Hash:   T4x4LongWordRecord;
  Hasher: TIdHash128;
  I:      Integer;
begin
  Result := 0;
  // This implementation's largely stolen from Appendix A.6 of RFC 3550.
  Hasher := TIdHashMessageDigest5.Create;
  try
    while not Self.AcceptableSSRC(Result) do begin
      // TODO: We should add more stuff here. RFC 3550's uses: pid, uid, gid and
      // hostid (but hostid is deprecated according to FreeBSD's gethostid(3)
      // manpage).
      Hash := Hasher.HashValue(DateTimeToStr(Now)
                             + IndyGetHostName
                             + IntToHex(CurrentProcessId, 8)
                             + IntToHex(TIdRandomNumber.NextCardinal, 8));

      Result := 0;
      for I := Low(Hash) to High(Hash) do
        Result := Result xor Hash[I];
    end;
  finally
    Hasher.Free;
  end;
end;

function TIdRTPSession.NextSequenceNo: TIdRTPSequenceNo;
begin
  Result := SequenceNo;
  SequenceNo := AddModuloWord(SequenceNo, 1);
end;

function TIdRTPSession.NothingSent: Boolean;
begin
  Result := Self.NoDataSent and Self.NoControlSent;
end;

procedure TIdRTPSession.ReceiveControl(RTCP: TIdRTCPPacket;
                                       Binding: TIdSocketHandle);
begin
  if RTCP.IsBye then begin
    Self.RemoveSources(RTCP as TIdRTCPBye);
  end
  else begin
    Self.AdjustAvgRTCPSize(RTCP);

    if RTCP is TIdRTCPMultiSSRCPacket then
      Self.AddControlSources(RTCP as TIdRTCPMultiSSRCPacket, Binding)
    else
      Self.AddControlSource(RTCP.SyncSrcID, Binding);

    Self.Member(RTCP.SyncSrcID).UpdateStatistics(RTCP);
  end;
end;

procedure TIdRTPSession.ReceiveData(RTP: TIdRTPPacket;
                                    Binding: TIdSocketHandle);
var
  I:    Integer;
  SSRC: TIdRTPMember;
begin
  if RTP.CollidesWith(Self.SyncSrcID) then
    Self.ResolveSSRCCollision;

  if not Self.IsMember(RTP.SyncSrcID) then
    Self.AddDataSource(RTP.SyncSrcID, Binding);

  for I := 0 to RTP.CsrcCount - 1 do
    Self.AddDataSource(RTP.CsrcIDs[I], Binding);

  SSRC := Self.Member(RTP.SyncSrcID);

  if SSRC.UpdateStatistics(RTP,
                           DateTimeToRTPTimestamp(Self.TimeOffsetFromStart(Now),
                                                  RTP.Payload.Encoding.ClockRate)) then begin
    // Valid, in-sequence RTP can be sent up the stack
  end;
end;

function TIdRTPSession.ReceiverCount: Cardinal;
var
  Members: TIdRTPMemberTable;
begin
  Members := Self.LockMembers;
  try
    Result := Members.ReceiverCount;
  finally
    Members.Free;
  end;
end;

procedure TIdRTPSession.RemoveMember(SSRC: Cardinal);
begin
  // We can't remove ourselves from a session - it makes no sense!
  if (SSRC <> Self.SyncSrcID) then
    Self.Members.Remove(SSRC);
end;

procedure TIdRTPSession.RemoveSender(SSRC: Cardinal);
begin
  Self.Senders.Remove(SSRC);
end;

procedure TIdRTPSession.RemoveTimedOutMembers;
var
  Members: TIdRTPMemberTable;
begin
  Members := Self.LockMembers;
  try
    Members.RemoveTimedOutMembersExceptFor(Members.MemberTimeout(Self),
                                           Self.SyncSrcID);
  finally
    Self.UnlockMembers;
  end;
end;

procedure TIdRTPSession.RemoveTimedOutSenders;
var
  Members: TIdRTPMemberTable;
begin
  // Self can itself be timed out as a sender. That's fine.
  Members := Self.LockMembers;
  try
    Members.RemoveTimedOutSenders(Members.SenderTimeout(Self));
  finally
    Self.UnlockMembers;
  end;
end;

procedure TIdRTPSession.ResolveSSRCCollision;
begin
  // 1. Issue a BYE to all members
  // 2. Calculate a new, unused SSRC
  // 3. Rejoin
  Self.LeaveSession(RTPLoopDetected);
  Self.SetSyncSrcId(Self.NewSSRC);
end;

procedure TIdRTPSession.SendControl(Packet: TIdRTCPPacket);
var
  I:       Integer;
  Members: TIdRTPMemberTable;
begin
  Packet.PrepareForTransmission(Self);

  if Packet.IsRTCP then
    Self.fNoControlSent := false;

  Members := Self.LockMembers;
  try
    for I := 0 to Members.Count - 1 do
      Agent.SendPacket(Members.MemberAt(I).ControlAddress,
                       Members.MemberAt(I).ControlPort,
                       Packet);
  finally
    Self.UnlockMembers;
  end;
end;

procedure TIdRTPSession.SendData(Data: TIdRTPPayload);
var
  Members: TIdRTPMemberTable;
begin
  Members := Self.LockMembers;
  try
    Self.SendDataToTable(Data, Members);
  finally
    Self.UnlockMembers;
  end;
end;

procedure TIdRTPSession.SendDataTo(Data: TIdRTPPayload;
                                   Host: String;
                                   Port: Cardinal);
var
  Member:    TIdRTPMember;
  TempTable: TIdRTPMemberTable;
begin
  TempTable := TIdRTPMemberTable.Create;
  try
    Member := TempTable.Add(Self.NewSSRC);
    Member.SourceAddress := Host;
    Member.SourcePort    := Port;

    Self.SendDataToTable(Data, TempTable);
  finally
    TempTable.Free;
  end;
end;

function TIdRTPSession.Sender(SSRC: Cardinal): TIdRTPMember;
begin
  Result := Self.Senders.Find(SSRC);
end;

function TIdRTPSession.SenderAt(Index: Cardinal): TIdRTPMember;
begin
  Result := Self.Senders.MemberAt(Index);
end;

function TIdRTPSession.SenderCount: Cardinal;
var
  Members: TIdRTPMemberTable;
begin
  Members := Self.LockMembers;
  try
    Result := Members.SenderCount;
  finally
    Self.UnlockMembers;
  end;
end;

procedure TIdRTPSession.SendReport;
var
  Report: TIdRTCPPacket;
begin
  Report := Self.CreateNextReport;
  try
    Self.SendControl(Report);
  finally
    Report.Free;
  end;
end;

function TIdRTPSession.TimeOffsetFromStart(WallclockTime: TDateTime): TDateTime;
begin
  Result := WallclockTime - Self.BaseTime;
end;

procedure TIdRTPSession.UnlockMembers;
begin
  Self.MemberLock.Release;
end;

//* TIdRTPSession Private methods **********************************************

function TIdRTPSession.AddAppropriateReportTo(Packet: TIdCompoundRTCPPacket): TIdRTCPReceiverReport;
begin
  if Self.IsSender then
    Result := Packet.AddSenderReport
  else
    Result := Packet.AddReceiverReport;
end;

procedure TIdRTPSession.AddControlSource(ID: Cardinal; Binding: TIdSocketHandle);
var
  Members: TIdRTPMemberTable;
begin
  Members := Self.LockMembers;
  try
    Members.SetControlBinding(ID, Binding);
  finally
    Self.UnlockMembers;
  end;
end;

procedure TIdRTPSession.AddControlSources(RTCP: TIdRTCPMultiSSRCPacket;
                                          Binding: TIdSocketHandle);
var
  IDs:     TCardinalDynArray;
  Members: TIdRTPMemberTable;
begin
  IDs := RTCP.GetAllSrcIDs;

  Members := Self.LockMembers;
  try
    Members.SetControlBindings(IDs, Binding);
  finally
    Self.UnlockMembers;
  end;
end;

procedure TIdRTPSession.AddDataSource(ID: Cardinal; Binding: TIdSocketHandle);
var
  Members: TIdRTPMemberTable;
begin
  Members := Self.LockMembers;
  try
    Members.SetDataBinding(ID, Binding);
  finally
    Self.UnlockMembers;
  end;
end;

procedure TIdRTPSession.AddReports(Packet: TIdCompoundRTCPPacket);
var
  I, J:    Cardinal;
  NumSrcs: Cardinal;
  Report:  TIdRTCPReceiverReport;  
begin
  // Sender Reports and Receiver Reports can hold at most 31 report blocks.
  // Sessions can have many more members. Therefore we pack at most
  // 31 report blocks into one report, and just keep adding reports to
  // the compound packet. For instance, if this session has 51 members,
  // we'd create a compound packet looking like this:
  // [RR with 31 members][RR with 20 members].

  // TODO: for sessions with a very large number of members (where the
  // size of the packet exceeds the probable MTU of the underlying
  // transport) we should send several sets of RRs/SRs covering (more or
  // less disjoint) subsets of the session members.

  Self.MemberLock.Acquire;
  try
    Report := Self.AddAppropriateReportTo(Packet);

    I := 0;
    while (I < Self.SenderCount) do begin
      J := 0;
      NumSrcs := Min(High(TIdRTCPReceptionCount), Self.SenderCount - I);
      Report.ReceptionReportCount := NumSrcs;
      while (J < NumSrcs) do begin
        Report.Reports[J].GatherStatistics(Self.SenderAt(I));
        Inc(J);
        Inc(I);
      end;

      if (I < Self.SenderCount) then
        Report := Self.AddAppropriateReportTo(Packet);
    end;
  finally
    Self.MemberLock.Release;
  end;
end;

procedure TIdRTPSession.AddSourceDesc(Packet: TIdCompoundRTCPPacket);
var
  Chunk: TIdRTCPSrcDescChunk;
  SDES:  TIdRTCPSourceDescription;
begin
  SDES := Packet.AddSourceDescription;
  Chunk := SDES.AddChunk;
  Chunk.SyncSrcID := Self.SyncSrcID;
  Chunk.AddCanonicalName(Self.CanonicalName);
end;

procedure TIdRTPSession.AdjustAvgRTCPSize(Control: TIdRTCPPacket);
begin
  Self.fAvgRTCPSize := Control.RealLength div 16
                     + (15*Self.AvgRTCPSize) div 16;
end;

procedure TIdRTPSession.AdjustTransmissionTime(Members: TIdRTPMemberTable);
var
  NextTransmissionTime:     TDateTime;
  PreviousTransmissionTime: TDateTime;
begin
  Members.AdjustTransmissionTime(Self.PreviousMemberCount,
                                 NextTransmissionTime,
                                 PreviousTransmissionTime);

  Self.NextTransmissionTime     := NextTransmissionTime;
  Self.PreviousTransmissionTime := PreviousTransmissionTime;
  Self.fPreviousMemberCount     := Members.Count;
end;

function TIdRTPSession.DefaultAssumedMTU: Cardinal;
begin
  Result := 1500;
end;

function TIdRTPSession.DefaultMissedReportTolerance: Cardinal;
begin
  Result := 5;
end;

function TIdRTPSession.DefaultNoControlSentAvgRTCPSize: Cardinal;
begin
  Result := 20; // a small SDES
end;

function TIdRTPSession.DefaultReceiverBandwidthFraction: Double;
begin
  Result := 1 - Self.DefaultSenderBandwidthFraction;
end;

function TIdRTPSession.DefaultSenderBandwidthFraction: Double;
begin
  Result := 0.25;
end;

procedure TIdRTPSession.IncSentOctetCount(N: Cardinal);
begin
  Inc(Self.fSentOctetCount, N);
end;

procedure TIdRTPSession.IncSentPacketCount;
begin
  Inc(Self.fSentPacketCount);
end;

procedure TIdRTPSession.RemoveSources(Bye: TIdRTCPBye);
var
  Members: TIdRTPMemberTable;
begin
  Members := Self.LockMembers;
  try
    Members.RemoveSources(Bye);
    Self.AdjustTransmissionTime(Members);
  finally
    Self.UnlockMembers;
  end;
end;

procedure TIdRTPSession.ResetSentOctetCount;
begin
  Self.fSentOctetCount := 0;
end;

procedure TIdRTPSession.ResetSentPacketCount;
begin
  Self.fSentPacketCount := 0;
end;

procedure TIdRTPSession.SendDataToTable(Data: TIdRTPPayload; Table: TIdRTPMemberTable);
var
  I:      Cardinal;
  Packet: TIdRTPPacket;
begin
  Packet := TIdRTPPacket.Create(Self.Profile);
  try
    Packet.ReadPayload(Data);

    if not Self.IsSender(Self.SyncSrcID) then
      Self.AddSender(Self.SyncSrcID);

    Packet.PrepareForTransmission(Self);

    Self.IncSentOctetCount(Data.Length);
    Self.IncSentPacketCount;

    if (Table.Count > 0) then
      for I := 0 to Table.Count - 1 do
        Agent.SendPacket(Table.MemberAt(I).SourceAddress,
                         Table.MemberAt(I).SourcePort,
                         Packet);
  finally
    Packet.Free;
  end;
end;

procedure TIdRTPSession.SetSyncSrcId(const Value: Cardinal);
begin
  Self.fSyncSrcID := Value;
  Self.ResetSentOctetCount;
  Self.ResetSentPacketCount;
end;

procedure TIdRTPSession.TransmissionTimeExpire(Sender: TObject);
var
  Members:                      TIdRTPMemberTable;
  PresumedNextTransmissionTime: TDateTime;
begin
  Self.TransmissionLock.Acquire;
  try
    Members := Self.LockMembers;
    try
      Members.RemoveTimedOutSenders(Members.SenderTimeout(Self));
      Members.RemoveTimedOutMembersExceptFor(Members.MemberTimeout(Self),
                                             Self.SyncSrcID);
      Self.AdjustTransmissionTime(Members);

      PresumedNextTransmissionTime := Self.PreviousTransmissionTime
                                    + OneMillisecond*Members.SendInterval(Self);

      if (PresumedNextTransmissionTime < Now) then
        Self.SendReport
      else begin
        // cf RFC 3550 Appendix A.7
        // We must redraw the interval.  Don't reuse the
        // one computed above, since it's not actually
        // distributed the same, as we are conditioned
        // on it being small enough to cause a packet to
        // be sent.
        Self.Timer.AddEvent(MilliSecondOfTheDay(Members.SendInterval(Self)),
                            Self.TransmissionTimeExpire);
      end;
    finally
      Self.UnlockMembers;
    end;
  finally
    Self.TransmissionLock.Release
  end;
end;

//******************************************************************************
//* TIdRTPPacketBuffer                                                         *
//******************************************************************************
//* TIdRTPPacketBuffer Public methods ******************************************

constructor TIdRTPPacketBuffer.Create;
begin
  inherited Create;

  Self.List := TObjectList.Create;
end;

destructor TIdRTPPacketBuffer.Destroy;
begin
  Self.Clear;
  Self.List.Free;

  inherited Destroy;
end;

procedure TIdRTPPacketBuffer.Add(Pkt: TIdRTPPacket);
begin
  Self.List.Insert(Self.AppropriateIndex(Pkt), Pkt);
end;

function TIdRTPPacketBuffer.Last: TIdRTPPacket;
begin
  Result := Self.PacketAt(0);
end;

procedure TIdRTPPacketBuffer.RemoveLast;
begin
  Self.List.Remove(Self.Last);
end;

//* TIdRTPPacketBuffer Private methods *****************************************

function TIdRTPPacketBuffer.AppropriateIndex(Pkt: TIdRTPPacket): Integer;
begin
  Result := 0;
  while (Result < Self.List.Count)
    and (Self.PacketAt(Result).Timestamp < Pkt.Timestamp) do
    Inc(Result);
end;

procedure TIdRTPPacketBuffer.Clear;
begin
  Self.List.Clear;
end;

function TIdRTPPacketBuffer.PacketAt(Index: Integer): TIdRTPPacket;
begin
  Result := Self.List[Index] as TIdRTPPacket;
end;

initialization
finalization
  GNullEncoding.Free;
  GNullPayload.Free;
end.
