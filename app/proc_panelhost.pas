(*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.

Copyright (c) Alexey Torgashin
*)
unit proc_panelhost;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Controls, StdCtrls, ExtCtrls, Buttons, Forms,
  ATButtons,
  ATFlatToolbar;

type
  TAppSideId = (
    cSideNone,
    cSideLeft,
    cSideBottom
    );

type
  { TAppPanelItem }

  TAppPanelItem = class
  public
    ItemCaption: string;
    ItemControl: TCustomControl;
    ItemModule: string;
    ItemMethod: string;
    ItemOnShow: TNotifyEvent;
    procedure InitControl(const ACaption: string; AControl: TCustomControl; AParent: TWinControl);
  end;

type
  TAppPanelOnCommand = procedure(const ACallback: string) of object;
  TAppPanelOnGetTitle = function(const ACaption: string): string of object;

type
  { TAppPanelHost }

  TAppPanelHost = class
  private
    function GetFloating: boolean;
    function GetVisible: boolean;
    procedure SetFloating(AValue: boolean);
    procedure SetVisible(AValue: boolean);
    procedure HandleButtonClick(Sender: TObject);
    procedure UpdateSplitter;
    procedure UpdateTitle;
  public
    PanelGrouper: TCustomControl;
    PanelRoot: TCustomControl;
    PanelTitle: TCustomControl;
    LabelTitle: TLabel;
    Panels: TFPList;
    Toolbar: TATFlatToolbar;
    Splitter: TSplitter;
    LastActivePanel: string;
    DefaultPanel: string;
    FormFloat: TForm;
    FormFloatBounds: TRect;
    OnHide: TNotifyEvent;
    OnCommand: TAppPanelOnCommand;
    OnCloseFloatForm: TCloseEvent;
    OnGetTranslatedTitle: TAppPanelOnGetTitle;
    constructor Create;
    destructor Destroy; override;
    property Floating: boolean read GetFloating write SetFloating;
    property Visible: boolean read GetVisible write SetVisible;
    function CaptionToPanelIndex(const ACaption: string): integer;
    function CaptionToButtonIndex(const ACaption: string): integer;
    function CaptionToControlHandle(const ACaption: string): PtrInt;
    function Add(const ACaption: string; AImageIndex: integer; AHandle: PtrInt; AOnPanelShow: TNotifyEvent): boolean;
    function AddEmpty(const ACaption: string; AImageIndex: integer; const AModule, AMethod: string): boolean;
    function Delete(const ACaption: string): boolean;
    procedure UpdateButtons;
    function UpdatePanels(const ACaption: string; AndFocus: boolean; ACheckExists: boolean): boolean;
    procedure InitFormFloat;
  end;

var
  AppPanels: array[TAppSideId] of TAppPanelHost;

implementation

const
  msgTitle = 'CudaText';

{ TAppPanelItem }

procedure TAppPanelItem.InitControl(const ACaption: string; AControl: TCustomControl; AParent: TWinControl);
begin
  ItemCaption:= ACaption;
  ItemControl:= AControl;
  ItemModule:= '';
  ItemMethod:= '';

  AControl.BorderStyle:= bsNone;
  AControl.Parent:= AParent;
  AControl.Align:= alClient;
end;

{ TAppPanelHost }

constructor TAppPanelHost.Create;
begin
  inherited Create;
  Panels:= TFPList.Create;
end;

destructor TAppPanelHost.Destroy;
begin
  Panels.Clear;
  FreeAndNil(Panels);
  inherited Destroy;
end;

function TAppPanelHost.GetVisible: boolean;
begin
  if Floating then
    Result:= FormFloat.Visible
  else
    Result:= PanelGrouper.Visible;
end;

procedure TAppPanelHost.SetFloating(AValue: boolean);
begin
  if GetFloating=AValue then exit;

  if Assigned(PanelTitle) then
    PanelTitle.Visible:= not AValue;

  if AValue then
  begin
    InitFormFloat;
    FormFloat.Show;
    UpdateTitle;

    PanelGrouper.Parent:= FormFloat;
    PanelGrouper.Align:= alClient;
    PanelGrouper.Show;
    Splitter.Hide;
  end
  else
  begin
    if Assigned(FormFloat) then
      FormFloat.Hide;

    PanelGrouper.Align:= Splitter.Align;
    PanelGrouper.Parent:= PanelRoot;
    Splitter.Visible:= PanelGrouper.Visible;
    UpdateSplitter;
  end
end;

procedure TAppPanelHost.SetVisible(AValue: boolean);
var
  Panel: TAppPanelItem;
  Btn: TATButton;
  N: integer;
begin
  if GetVisible=AValue then exit;

  PanelGrouper.Visible:= AValue;
  if Floating then
  begin
    FormFloat.Visible:= AValue;
  end
  else
  begin
    Splitter.Visible:= AValue;
    if AValue then
      UpdateSplitter;
  end;

  if AValue then
  begin
    if LastActivePanel='' then
      LastActivePanel:= DefaultPanel;

    if LastActivePanel<>'' then
    begin
      N:= CaptionToPanelIndex(LastActivePanel);
      if N>=0 then
      begin
        Panel:= TAppPanelItem(Panels[N]);
        if Assigned(Panel.ItemOnShow) then
          Panel.ItemOnShow(nil);
      end;

      N:= CaptionToButtonIndex(LastActivePanel);
      if N>=0 then
      begin
        Btn:= Toolbar.Buttons[N];
        Btn.OnClick(Btn);
      end;

      UpdateTitle;
    end;
  end
  else
  if Assigned(OnHide) then
    OnHide(nil);

  UpdateButtons;
end;

function TAppPanelHost.GetFloating: boolean;
begin
  Result:= Assigned(FormFloat) and (PanelGrouper.Parent=FormFloat);
end;

function TAppPanelHost.CaptionToPanelIndex(const ACaption: string): integer;
var
  i: integer;
begin
  Result:= -1;
  for i:= 0 to Panels.Count-1 do
    with TAppPanelItem(Panels[i]) do
      if ItemCaption=ACaption then
        exit(i);
end;

function TAppPanelHost.CaptionToButtonIndex(const ACaption: string): integer;
var
  i: integer;
begin
  Result:= -1;
  for i:= 0 to Toolbar.ButtonCount-1 do
    if SameText(Toolbar.Buttons[i].Caption, ACaption) then
      exit(i);
end;

function TAppPanelHost.CaptionToControlHandle(const ACaption: string): PtrInt;
var
  Num: integer;
begin
  Result:= 0;
  Num:= CaptionToPanelIndex(ACaption);
  if Num<0 then exit;

  with TAppPanelItem(Panels[Num]) do
    if Assigned(ItemControl) then
      Result:= PtrInt(ItemControl);
end;

function TAppPanelHost.Add(const ACaption: string; AImageIndex: integer;
  AHandle: PtrInt; AOnPanelShow: TNotifyEvent): boolean;
var
  Panel: TAppPanelItem;
  Num: integer;
  bExist: boolean;
begin
  Num:= CaptionToPanelIndex(ACaption);
  bExist:= Num>=0;

  if bExist then
    Panel:= TAppPanelItem(Panels[Num])
  else
  begin
    Panel:= TAppPanelItem.Create;
    Panel.ItemOnShow:= AOnPanelShow;
    Panels.Add(Panel);
  end;

  if AHandle<>0 then
    Panel.InitControl(ACaption, TCustomForm(AHandle), PanelGrouper);

  if not bExist then
  begin
    Toolbar.AddButton(AImageIndex, @HandleButtonClick, ACaption, ACaption, '', false);
    Toolbar.UpdateControls;
  end;

  Result:= true;
end;

function TAppPanelHost.AddEmpty(const ACaption: string; AImageIndex: integer;
  const AModule, AMethod: string): boolean;
var
  Panel: TAppPanelItem;
begin
  if CaptionToPanelIndex(ACaption)>=0 then exit(false);

  Panel:= TAppPanelItem.Create;
  Panel.ItemCaption:= ACaption;
  Panel.ItemControl:= nil;
  Panel.ItemModule:= AModule;
  Panel.ItemMethod:= AMethod;
  Panels.Add(Panel);

  //save module/method to Btn.DataString
  Toolbar.AddButton(AImageIndex, @HandleButtonClick, ACaption, ACaption,
    AModule+'.'+AMethod,
    false);
  Toolbar.UpdateControls;

  Result:= true;
end;

function TAppPanelHost.Delete(const ACaption: string): boolean;
var
  Num, i: integer;
begin
  Num:= CaptionToButtonIndex(ACaption);
  Result:= Num>=0;
  if Result then
  begin
    Toolbar.Buttons[Num].Free;
    Toolbar.UpdateControls;

    for i:= 0 to Panels.Count-1 do
      with TAppPanelItem(Panels[i]) do
        if ItemCaption=ACaption then
        begin
          if Assigned(ItemControl) then
            ItemControl.Hide;
          Panels.Delete(i);
          Break;
        end;
  end;
end;

procedure TAppPanelHost.UpdateButtons;
var
  Btn: TATButton;
  bVis: boolean;
  i: integer;
begin
  bVis:= Visible;
  for i:= 0 to Toolbar.ButtonCount-1 do
  begin
    Btn:= Toolbar.Buttons[i];
    Btn.Checked:= bVis and SameText(Btn.Caption, LastActivePanel);
  end;
end;

function TAppPanelHost.UpdatePanels(const ACaption: string; AndFocus: boolean;
  ACheckExists: boolean): boolean;
var
  Ctl: TCustomControl;
  bFound: boolean;
  i: integer;
begin
  if ACheckExists then
  begin
    Result:= CaptionToButtonIndex(ACaption)>=0;
    if not Result then exit;
  end
  else
    Result:= true;

  LastActivePanel:= ACaption;
  Visible:= true;
  UpdateButtons;
  UpdateTitle;

  for i:= 0 to Panels.Count-1 do
  begin
    Ctl:= TAppPanelItem(Panels[i]).ItemControl;
    if Assigned(Ctl) then
      Ctl.Hide;
  end;

  for i:= 0 to Panels.Count-1 do
    with TAppPanelItem(Panels[i]) do
    begin
      if ItemCaption='' then Continue;
      bFound:= ItemCaption=ACaption;
      if bFound then
      begin
        Ctl:= ItemControl;
        if Assigned(Ctl) then
        begin
          Ctl.Show;
          if AndFocus then
            if PanelGrouper.Visible then
              if Ctl.Visible and Ctl.CanFocus then
                Ctl.SetFocus;
        end
        else
        if (ItemModule<>'') and (ItemMethod<>'') then
          OnCommand(ItemModule+'.'+ItemMethod);
        Break;
      end;
    end;
end;

procedure TAppPanelHost.InitFormFloat;
begin
  if not Assigned(FormFloat) then
  begin
    FormFloat:= TForm.CreateNew(Application.MainForm);
    FormFloat.Position:= poDesigned;
    FormFloat.BoundsRect:= FormFloatBounds;
    FormFloat.BorderIcons:= [biSystemMenu, biMaximize];
    FormFloat.ShowInTaskBar:= stNever;
    FormFloat.OnClose:= OnCloseFloatForm;
  end;
end;

procedure TAppPanelHost.HandleButtonClick(Sender: TObject);
var
  Btn: TATButton;
  SCaption: string;
  NPanel: integer;
begin
  Btn:= Sender as TATButton;
  SCaption:= Btn.Caption;

  if Btn.Checked or (SCaption='') then
  begin
    Btn.Checked:= false;
    Visible:= false;
    exit
  end;

  //avoid plugin call if panel already inited
  NPanel:= CaptionToPanelIndex(SCaption);
  if (NPanel>=0) and (TAppPanelItem(Panels[NPanel]).ItemControl=nil) then
    OnCommand(Btn.DataString);

  UpdatePanels(SCaption, true, false);
end;

procedure TAppPanelHost.UpdateSplitter;
begin
  case Splitter.Align of
    alLeft:
      Splitter.Left:= PanelGrouper.Width;
    alBottom:
      Splitter.Top:= PanelGrouper.Top-8;
    alRight:
      Splitter.Left:= PanelGrouper.Left-8;
    else
      begin end;
  end;
end;

procedure TAppPanelHost.UpdateTitle;
var
  S: string;
begin
  S:= OnGetTranslatedTitle(LastActivePanel);
  if Assigned(LabelTitle) then
    LabelTitle.Caption:= S;
  if Assigned(FormFloat) then
    FormFloat.Caption:= S+' - '+msgTitle;
end;

var
  side: TAppSideId;

initialization

  for side in TAppSideId do
    if side<>cSideNone then
      AppPanels[side]:= TAppPanelHost.Create;

finalization

  for side in TAppSideId do
    if side<>cSideNone then
      FreeAndNil(AppPanels[side]);

end.
