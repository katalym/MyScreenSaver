unit uPreview;

{ Preview mode (/p <hwnd>): Windows shows the screensaver in the small monitor of the
  "Screen Saver Settings" dialog. We show one random photo there. }

interface

uses
  Winapi.Windows;

procedure RunPreview(AParentWnd: HWND);

implementation

uses
  System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.Graphics,
  uConfig, uMedia, uViewer;

type
  TPreviewForm = class(TForm)
  private
    FImage: TImage;
    FTimer: TTimer;
    FCatalog: TMediaCatalog;
    FSampler: TQuickSampler;
    FLoaded: Boolean;
    FTicks: Integer;
    procedure TimerTick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  GParentWnd: HWND;

constructor TPreviewForm.Create(AOwner: TComponent);
var
  vRect: TRect;
begin
  CreateNew(AOwner);
  BorderStyle := bsNone;
  Color := clBlack;
  ParentWindow := GParentWnd;
  Winapi.Windows.GetClientRect(GParentWnd, vRect);
  SetBounds(0, 0, vRect.Right - vRect.Left, vRect.Bottom - vRect.Top);
  FImage := TImage.Create(Self);
  FImage.Parent := Self;
  FImage.Align := alClient;
  FImage.Center := True;
  FImage.Proportional := True;
  FImage.Stretch := True;
  FCatalog := TMediaCatalog.Create;
  FSampler := TQuickSampler.Create(FCatalog);
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 200;
  FTimer.OnTimer := TimerTick;
end;

destructor TPreviewForm.Destroy;
begin
  FSampler.Terminate;
  FSampler.WaitFor;
  FreeAndNil(FSampler);
  FreeAndNil(FCatalog);
  inherited;
end;

procedure TPreviewForm.TimerTick(Sender: TObject);
var
  vItem: TMediaItem;
begin
  Inc(FTicks);
  // the settings dialog was closed: the parent window is gone
  if not IsWindow(GParentWnd) then
  begin
    Application.Terminate;
    Exit;
  end;
  if FLoaded or (FTicks > 50) then   // one photo, or give up after ~10 s
    Exit;
  if FCatalog.PopQuick(vItem) then
  begin
    FLoaded := True;
    FCatalog.Ready := True;          // stops the sampler
    try
      LoadPhotoPicture(FImage.Picture, vItem.Location);
    except
      FImage.Picture.Assign(nil);
    end;
  end;
end;

procedure RunPreview(AParentWnd: HWND);
var
  vForm: TPreviewForm;
begin
  if not IsWindow(AParentWnd) then
    Exit;
  GParentWnd := AParentWnd;
  Application.MainFormOnTaskbar := False;
  Application.CreateForm(TPreviewForm, vForm);
  Application.Run;
end;

end.
