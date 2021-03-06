unit NtUtils.Svc;

interface

uses
  Winapi.WinNt, NtUtils.Exceptions, NtUtils.Objects, Winapi.Svc,
  DelphiUtils.AutoObject;

type
  TScmHandle = Winapi.Svc.TScmHandle;
  IScmHandle = DelphiUtils.AutoObject.IHandle;

  TScmAutoHandle = class(TCustomAutoHandle, IScmHandle)
    destructor Destroy; override;
  end;

  TServiceConfig = record
    ServiceType: Cardinal;
    StartType: TServiceStartType;
    ErrorControl: TServiceErrorControl;
    TagId: Cardinal;
    BinaryPathName: String;
    LoadOrderGroup: String;
    ServiceStartName: String;
    DisplayName: String;
  end;

// Open a handle to SCM
function ScmxConnect(out hxScm: IScmHandle; DesiredAccess: TAccessMask;
  ServerName: String = ''): TNtxStatus;

// Open a service
function ScmxOpenService(out hxSvc: IScmHandle; ServiceName: String;
  DesiredAccess: TAccessMask; hxScm: IScmHandle = nil): TNtxStatus;

// Create a service
function ScmxCreateService(out hxSvc: IScmHandle; CommandLine, ServiceName,
  DisplayName: String; StartType: TServiceStartType = ServiceDemandStart;
  hxScm: IScmHandle = nil): TNtxStatus;

// Start a service
function ScmxStartService(hSvc: TScmHandle; Parameters: TArray<String> = nil):
  TNtxStatus;

// Send a control to a service
function ScmxControlService(hSvc: TScmHandle; Control: TServiceControl;
  out ServiceStatus: TServiceStatus): TNtxStatus;

// Delete a service
function ScmxDeleteService(hSvc: TScmHandle): TNtxStatus;

// Query service config
function ScmxQueryConfigService(hSvc: TScmHandle; out Config: TServiceConfig)
  : TNtxStatus;

// Query service status and process information
function ScmxQueryProcessStatusService(hSvc: TScmHandle;
  out Info: TServiceStatusProcess): TNtxStatus;

type
  NtxService = class
    // Query fixed-size information
    class function Query<T>(hSvc: TScmHandle;
      InfoClass: TServiceConfigLevel; out Buffer: T): TNtxStatus; static;
  end;

// Query variable-size service information
function ScmxQueryService(hSvc: TScmHandle; InfoClass: TServiceConfigLevel;
  out xMemory: IMemory): TNtxStatus;

// Set service information
function ScmxSetService(hSvc: TScmHandle; InfoClass: TServiceConfigLevel;
  Buffer: Pointer): TNtxStatus;

// Query service description
function ScmxQueryDescriptionService(hSvc: TScmHandle; out Description: String):
  TNtxStatus;

// Query list of requires privileges for a service
function ScmxQueryRequiredPrivilegesService(hSvc: TScmHandle; out Privileges:
  TArray<String>): TNtxStatus;

implementation

uses
  NtUtils.Access.Expected, Ntapi.ntstatus, DelphiUtils.Arrays;

destructor TScmAutoHandle.Destroy;
begin
  if FAutoRelease then
    CloseServiceHandle(FHandle);
  inherited;
end;

function ScmxConnect(out hxScm: IScmHandle; DesiredAccess: TAccessMask;
  ServerName: String): TNtxStatus;
var
  hScm: TScmHandle;
  pServerName: PWideChar;
begin
  if ServerName <> '' then
    pServerName := PWideChar(ServerName)
  else
    pServerName := nil;

  Result.Location := 'OpenSCManagerW';
  Result.LastCall.CallType := lcOpenCall;
  Result.LastCall.AccessMask := DesiredAccess;
  Result.LastCall.AccessMaskType := @ScmAccessType;

  hScm := OpenSCManagerW(pServerName, nil, DesiredAccess);
  Result.Win32Result := (hScm <> 0);

  if Result.IsSuccess then
    hxScm := TScmAutoHandle.Capture(hScm);
end;

function ScmxpEnsureConnected(var hxScm: IScmHandle; DesiredAccess: TAccessMask)
  : TNtxStatus;
begin
  if not Assigned(hxScm) then
    Result := ScmxConnect(hxScm, DesiredAccess)
  else
    Result.Status := STATUS_SUCCESS
end;

function ScmxOpenService(out hxSvc: IScmHandle; ServiceName: String;
  DesiredAccess: TAccessMask; hxScm: IScmHandle): TNtxStatus;
var
  hSvc: TScmHandle;
begin
  Result := ScmxpEnsureConnected(hxScm, SC_MANAGER_CONNECT);

  if not Result.IsSuccess then
    Exit;

  Result.Location := 'OpenServiceW';
  Result.LastCall.CallType := lcOpenCall;
  Result.LastCall.AccessMask := DesiredAccess;
  Result.LastCall.AccessMaskType := @ServiceAccessType;
  Result.LastCall.Expects(SC_MANAGER_CONNECT, @ScmAccessType);

  hSvc := OpenServiceW(hxScm.Handle, PWideChar(ServiceName), DesiredAccess);
  Result.Win32Result := (hSvc <> 0);

  if Result.IsSuccess then
    hxSvc := TScmAutoHandle.Capture(hSvc);
end;

function ScmxCreateService(out hxSvc: IScmHandle; CommandLine, ServiceName,
  DisplayName: String; StartType: TServiceStartType; hxScm: IScmHandle)
  : TNtxStatus;
var
  hSvc: TScmHandle;
begin
  Result := ScmxpEnsureConnected(hxScm, SC_MANAGER_CREATE_SERVICE);

  if not Result.IsSuccess then
    Exit;

  Result.Location := 'CreateServiceW';
  Result.LastCall.Expects(SC_MANAGER_CREATE_SERVICE, @ScmAccessType);

  hSvc := CreateServiceW(hxScm.Handle, PWideChar(ServiceName),
    PWideChar(DisplayName), SERVICE_ALL_ACCESS, SERVICE_WIN32_OWN_PROCESS,
    StartType, ServiceErrorNormal, PWideChar(CommandLine), nil, nil, nil, nil,
    nil);
  Result.Win32Result := (hSvc <> 0);

  if Result.IsSuccess then
    hxSvc := TScmAutoHandle.Capture(hSvc);
end;

function ScmxStartService(hSvc: TScmHandle; Parameters: TArray<String>):
  TNtxStatus;
var
  i: Integer;
  Params: TArray<PWideChar>;
begin
  SetLength(Params, Length(Parameters));

  for i := 0 to High(Params) do
    Params[i] := PWideChar(Parameters[i]);

  Result.Location := 'StartServiceW';
  Result.LastCall.Expects(SERVICE_START, @ServiceAccessType);

  Result.Win32Result := StartServiceW(hSvc, Length(Params), Params);
end;

function ScmxControlService(hSvc: TScmHandle; Control: TServiceControl;
  out ServiceStatus: TServiceStatus): TNtxStatus;
begin
  Result.Location := 'ControlService';
  Result.LastCall.CallType := lcQuerySetCall;
  Result.LastCall.InfoClass := Cardinal(Control);
  Result.LastCall.InfoClassType := TypeInfo(TServiceControl);
  RtlxComputeServiceControlAccess(Result.LastCall, Control);

  Result.Win32Result := ControlService(hSvc, Control, ServiceStatus);
end;

function ScmxDeleteService(hSvc: TScmHandle): TNtxStatus;
begin
  Result.Location := 'DeleteService';
  Result.LastCall.Expects(_DELETE, @ServiceAccessType);
  Result.Win32Result := DeleteService(hSvc);
end;

function ScmxQueryConfigService(hSvc: TScmHandle; out Config: TServiceConfig)
  : TNtxStatus;
var
  Buffer: PQueryServiceConfigW;
  BufferSize, Required: Cardinal;
begin
  Result.Location := 'QueryServiceConfigW';
  Result.LastCall.Expects(SERVICE_QUERY_CONFIG, @ServiceAccessType);

  BufferSize := 0;
  repeat
    Buffer := AllocMem(BufferSize);

    Required := 0;
    Result.Win32Result := QueryServiceConfigW(hSvc, Buffer, BufferSize,
      Required);

    if not Result.IsSuccess then
      FreeMem(Buffer);

  until not NtxExpandBuffer(Result, BufferSize, Required);

  if not Result.IsSuccess then
    Exit;

  Config.ServiceType := Buffer.ServiceType;
  Config.StartType := Buffer.StartType;
  Config.ErrorControl := Buffer.ErrorControl;
  Config.TagId := Buffer.TagId;
  Config.BinaryPathName := String(Buffer.BinaryPathName);
  Config.LoadOrderGroup := String(Buffer.LoadOrderGroup);
  Config.ServiceStartName := String(Buffer.ServiceStartName);
  Config.DisplayName := String(Buffer.DisplayName);

  FreeMem(Buffer);
end;

function ScmxQueryProcessStatusService(hSvc: TScmHandle;
  out Info: TServiceStatusProcess): TNtxStatus;
var
  Required: Cardinal;
begin
  Result.Location := 'QueryServiceStatusEx';
  Result.LastCall.CallType := lcQuerySetCall;
  Result.LastCall.InfoClass := Cardinal(ScStatusProcessInfo);
  Result.LastCall.InfoClassType := TypeInfo(TScStatusType);
  Result.LastCall.Expects(SERVICE_QUERY_STATUS, @ServiceAccessType);

  Result.Win32Result := QueryServiceStatusEx(hSvc, ScStatusProcessInfo,
    @Info, SizeOf(Info), Required);
end;

class function NtxService.Query<T>(hSvc: TScmHandle;
  InfoClass: TServiceConfigLevel; out Buffer: T): TNtxStatus;
var
  Required: Cardinal;
begin
  Result.Location := 'QueryServiceConfig2W';
  Result.LastCall.Expects(SERVICE_QUERY_CONFIG, @ServiceAccessType);
  Result.LastCall.CallType := lcQuerySetCall;
  Result.LastCall.InfoClass := Cardinal(InfoClass);
  Result.LastCall.InfoClassType := TypeInfo(TServiceConfigLevel);
  Result.Win32Result := QueryServiceConfig2W(hSvc, InfoClass, @Buffer,
    SizeOf(Buffer), Required);
end;

function ScmxQueryService(hSvc: TScmHandle; InfoClass: TServiceConfigLevel;
  out xMemory: IMemory): TNtxStatus;
var
  Buffer: Pointer;
  BufferSize, Required: Cardinal;
begin
  Result.Location := 'QueryServiceConfig2W';
  Result.LastCall.Expects(SERVICE_QUERY_CONFIG, @ServiceAccessType);
  Result.LastCall.CallType := lcQuerySetCall;
  Result.LastCall.InfoClass := Cardinal(InfoClass);
  Result.LastCall.InfoClassType := TypeInfo(TServiceConfigLevel);

  BufferSize := 0;
  repeat
    Buffer := AllocMem(BufferSize);

    Required := 0;
    Result.Win32Result := QueryServiceConfig2W(hSvc, InfoClass, Buffer,
      BufferSize, Required);

    if not Result.IsSuccess then
    begin
      FreeMem(Buffer);
      Buffer := nil;
    end;
  until not NtxExpandBuffer(Result, BufferSize, Required);

  if Result.IsSuccess then
    xMemory := TAutoMemory.Capture(Buffer, BufferSize);
end;

function ScmxSetService(hSvc: TScmHandle; InfoClass: TServiceConfigLevel;
  Buffer: Pointer): TNtxStatus;
begin
  Result.Location := 'ChangeServiceConfig2W';
  Result.LastCall.Expects(SERVICE_CHANGE_CONFIG, @ServiceAccessType);
  Result.LastCall.CallType := lcQuerySetCall;
  Result.LastCall.InfoClass := Cardinal(InfoClass);
  Result.LastCall.InfoClassType := TypeInfo(TServiceConfigLevel);
  Result.Win32Result := ChangeServiceConfig2W(hSvc, InfoClass, Buffer);
end;

function ScmxQueryDescriptionService(hSvc: TScmHandle; out Description: String):
  TNtxStatus;
var
  xMemory: IMemory;
begin
  Result := ScmxQueryService(hSvc, ServiceConfigDescription, xMemory);

  if Result.IsSuccess then
    Description := String(PServiceDescription(xMemory.Address).Description);
end;

function ScmxQueryRequiredPrivilegesService(hSvc: TScmHandle; out Privileges:
  TArray<String>): TNtxStatus;
var
  xMemory: IMemory;
  Buffer: PServiceRequiredPrivilegesInfo;
begin
  Result := ScmxQueryService(hSvc, ServiceConfigRequiredPrivilegesInfo,
    xMemory);

  if Result.IsSuccess then
  begin
    Buffer := xMemory.Address;

    if Assigned(Buffer.RequiredPrivileges) and (xMemory.Size >
      SizeOf(TServiceRequiredPrivilegesInfo)) then
      Privileges := ParseMultiSz(Buffer.RequiredPrivileges,
        (xMemory.Size - SizeOf(TServiceRequiredPrivilegesInfo)) div
        SizeOf(WideChar))
    else
      SetLength(Privileges, 0);
  end;
end;

end.
