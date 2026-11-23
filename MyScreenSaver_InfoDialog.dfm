object InfoForm: TInfoForm
  Left = 0
  Top = 0
  AutoSize = True
  BorderStyle = bsDialog
  Caption = 'Information'
  ClientHeight = 250
  ClientWidth = 560
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Padding.Left = 16
  Padding.Top = 16
  Padding.Right = 16
  Padding.Bottom = 12
  Position = poOwnerFormCenter
  PixelsPerInch = 96
  TextHeight = 15
  object memText: TMemo
    Left = 16
    Top = 16
    Width = 528
    Height = 120
    Cursor = crIBeam
    BorderStyle = bsNone
    Color = clBtnFace
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -15
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssNone
    TabOrder = 0
    WordWrap = True
  end
  object bvlText: TBevel
    Left = 16
    Top = 146
    Width = 528
    Height = 2
    Shape = bsTopLine
  end
  object lblCache: TLabel
    Left = 16
    Top = 160
    Width = 300
    Height = 17
    Caption = 'Cache'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    Transparent = True
  end
  object btnOpenCache: TSpeedButton
    Left = 330
    Top = 157
    Width = 70
    Height = 23
    Caption = 'Open Cache'
    Flat = True
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
  end
  object btnClearShown: TSpeedButton
    Left = 404
    Top = 157
    Width = 70
    Height = 23
    Caption = 'Clear shown'
    Flat = True
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
  end
  object btnClearAll: TSpeedButton
    Left = 478
    Top = 157
    Width = 66
    Height = 23
    Caption = 'Clear all'
    Flat = True
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
  end
  object bvlButtons: TBevel
    Left = 16
    Top = 192
    Width = 528
    Height = 2
    Shape = bsTopLine
  end
  object btnShare: TButton
    Left = 16
    Top = 208
    Width = 120
    Height = 25
    Caption = '&Share...'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -13
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    TabOrder = 1
  end
  object btnDelete: TButton
    Left = 256
    Top = 208
    Width = 100
    Height = 25
    Caption = '&Delete'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -13
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    TabOrder = 2
  end
  object btnClose: TButton
    Left = 444
    Top = 208
    Width = 100
    Height = 25
    Caption = '&Close'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -13
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    TabOrder = 3
  end
end
