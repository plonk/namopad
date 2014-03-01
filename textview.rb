# -*- coding: utf-8 -*-
TIME_STAMP = 'Time-stamp: "2012-11-09 04:39:34 plonk"'
require "gtk2"
include Gtk
require "nkf"
require "mac_japanese" 
require "cgi"
require "stringio"

$PROGRAM_NAME = File.absolute_path($PROGRAM_NAME)

# このスクリプトを実行している ruby.exe とか rubyw.exe のパスを得る
def get_exec_filename
  require "Win32API"

  buf = "\0" * 256
  Win32API.new("kernel32", "GetModuleFileName", "LPL", "L").call(0, buf, 256)
  return  buf.rstrip
end

class String
  # 文字列の幅を返す
  # UTF8 で３バイトエンコードされる文字を全角とみなす
  def jsize
    n = 0
    split(//).each do |c|
      if c.bytesize == 3
        n += 2
      else
        n += 1
      end
    end
    return n
  end
end

class Gtk::TextTag
  attr_accessor :link
end

# スクラッチバッファーの名前。無題とかでもいい
SCRATCH_BUFFER_NAME = "*scratch*"

# Shift_JIS のマイクロソフト拡張部分の文字の色
CP932_FOREGROUND= "brown"
# CP932 で表現できない Unicode 文字の色
UNICODE_FOREGROUND = "blue"

# ファイルを開くときはバイナリモードで！
# Encoding.default_external = "cp932"
Encoding.default_external = "utf-8"
Encoding.default_internal = "utf-8"
RC.parse("./gtkrc-text")
$APPLICATION_NAME = "ナモ帳"
$WINDOWS ||= [] # main application windows

# ASCII 文字から Gdk::Keyval の名前への変換テーブル
ASCII2NAME = {
  "!"=>"exclam",
  "\"" =>"quotedbl",
  '#'=>"numbersign",
  "$"=>"dollar",
  "%"=>"percent",
  "&"=>"ampersand",
  "'"=>"apostrophe",
  "("=>"parenleft",
  ")"=>"parenright",
  "*"=>"asterisk",
  "+"=>"plus",
  ","=>"comma",
  "-"=>"minus",
  "."=>"period",
  "/"=>"slash",
  ":"=>"colon",
  ";"=>"semicolon",
  "<"=>"less",
  "="=>"equal",
  ">"=>"greater",
  "?"=>"question",
  "@"=>"at",
  "["=>"bracketleft",
  "\\"=>"backslash",
  "]"=>"bracketright",
  "^"=>"asciicircum",
  "_"=>"underscore",
  "`"=>"grave",
  "{"=>"braceleft",
  "|"=>"bar",
  "}"=>"braceright",
  "~"=>"asciitilde",
}

# アスキー文字を Gdk::Keyval に変換する
def ascii2name(c)
  raise unless c.size == 1
  return ASCII2NAME[c]
end

# Gdk::Keyval::GDK_? からASCII文字へ。
# 数値的に一緒な気もする
def name2ascii(name)
  return ASCII2NAME.invert[name]
end

# 配列のサイズを概算する
# アンドゥーバッファのフットプリントを測るために
# 書いた
def size_recursive(a)
  if a.is_a? Enumerable 
    n = 0
    a.each do |x|
      n += size_recursive(x)
    end
    return n
  else
    begin
      return a.size
    rescue
      return 0
    end
  end
end

# UnicodeData.txt の情報をもとに、コードポイントから
# 文字の名前を得るオブジェクトを作るクラス。
class UnicodeData
  # aaa
  def initialize
    @file = File.new("UnicodeData.txt", "r")
    @lines = []
    @file.each_line do |line|
      line.chomp!
      @lines << line
    end
  end

  # 文字の名前を返す
  def [](codepoint)
    begin
      match = @lines.grep(/^#{codepoint};/)
      return nil if match.empty?
      a = match[0].split(/;/)
      return a[1]
    rescue
      puts "error occured #{codepoint.inspect} #{match.inspect}"
      raise
    end
  end
end

# UnicodeData.txt を使って文字情報を引くオブジェクト
$UNICODE_DATA = UnicodeData.new

# 文字のタイプを返す。
# タグの名前として使われる。
def chartype(ch)
  begin
    ch.encode("Shift_JIS")
    return "ordinary"
  rescue Encoding::UndefinedConversionError
    begin
      ch.encode("CP932")
      return "cp932"
    rescue Encoding::UndefinedConversionError
      return "unicode"
    end
  end
end

# キー操作を表した文字列を Keyval と 修飾キーマスクの組みを
# 要素とした配列に翻訳する。e.x.:
# "C-xC-f" => [ [GDK_x, CONTROL_MASK], [GDK_f, CONTROL_MASK] ]
# "C-xs"   => [ [GDK_x, CONTROL_MASK], [GDK_s, 0] ]
# "C-S-e"  => [ [GDK_e, CONTROL_MASK|SHIFT_MASK] ]
def str2key(keystr)
  rv = []
  keystr.scan(/((?:[CMS]-)*)(<\w+>|[!-~])/) do |one_stroke| # てきとー
    mod = $1; key = $2
    mask = 0
    mod.scan(/[CMS]/) do |m|
      case m
      when "C"
        mask = mask | Gdk::Window::CONTROL_MASK.to_i
      when "M"
        mask = mask | Gdk::Window::MOD1_MASK.to_i
      when "S"
#        mask = mask | Gdk::Window::SHIFT_MASK.to_i
      end
    end
#    mask |= Gdk::Window::SHIFT_MASK.to_i if key =~ /^[A-Z]$/
    if key =~ /^<(.+)>$/
      key = $1
    end
    key = ascii2name(key) unless key =~ /^[A-Za-z0-9]/
    begin
      keysym = eval("Gdk::Keyval::GDK_#{key}")
    rescue NameError
      raise("そんなキーないです")
    end
    rv << [keysym, mask]
  end
  return rv
end

# str2key の反対
# １つのキーストロークを文字列表現にする
def key2str(keysym, mask)
  str = ""
  str += "C-" if mask & Gdk::Window::CONTROL_MASK != 0
  str += "M-" if mask & Gdk::Window::MOD1_MASK != 0 
  str += "S-" if mask & Gdk::Window::SHIFT_MASK != 0
  name = Gdk::Keyval.to_name(keysym)
  if name =~ /^[A-Za-z1-90]$/
    str += name
  else
    c = name2ascii(name)
    if c
      str += c
    else
      str += "<#{name}>"
    end
  end
  return str
end

# キーマップを表すクラス
# キーを定義したり、定義を取り消したり
# 対応付けられたシンボルや Proc オブジェクトを検索できる。
class Keymap
  # 設定されていると1ストロークキーバインドのルックアップが失敗した
  # 時点で Proc オブジェクトを実行し、エントリーが見つからなかったことにする
  # isearch で意味のないコマンドが入力された時に isearch を終了し、
  # メジャーモードやグローバルのキーバインドを実行させるのに使う
  # ことを意図している。名前は on_lookup_failure とかの方がいいかもね。
  attr_accessor :default_proc

  def initialize
    @keymap = []
    @default_proc = nil
  end

  # キーにシンボルか Proc を結びつける
  def define_key(str, sym)
    if sym.is_a? Symbol
      cmd = sym # proc { self.method(sym).call }
    else
      cmd = sym # i.e. proc
    end
    undefine_key(str)

    keystroke = str2key(str)

    @keymap << [keystroke, cmd]
  end

  # キー定義を削除する
  def undefine_key(keystroke)
    found_p = false
    keystroke = str2key(keystroke) if keystroke.is_a? String
    @keymap.delete_if { |entry|
      entry[0] == keystroke and found_p = true
    }
    return found_p
  end

  # a1 が a2 で始まる場合は true を返す。
  # otherwise false.
  def start_with_p(a1, a2)
    a2.each_with_index do |x, i|
      return false if a1[i] != x
    end
    return true
  end

  # 前方マッチがあった場合は、true を
  # 完全マッチがあった場合は Proc か Symbol を
  # なにもなかった場合は nil を返す
  def lookup(stroke)
    stroke = str2key(stroke) if stroke.is_a? String
    # 完全マッチを探す
    @keymap.each do |entry|
      if entry[0] == stroke
        return entry[1]
      end
    end
    # デフォルトがある場合は部分マッチを見ない
    if @default_proc
      rv = @default_proc.call
      # キーが見つからなかったことにする
      return nil
    end
    # 部分マッチを探す
    @keymap.each do |entry|
      return true if start_with_p(entry[0], stroke)
    end
    return nil
  end

  # キーマップのエントリーごとにブロックを実行する
  def each
    @keymap.each do |entry|
      yield(entry)
    end
  end
end

# メジャーモードを表すクラス
# on_change の Proc オブジェクトがバッファーの変更時に
# 呼び出される
# on_load の Proc オブジェクトがバッファにファイルの
# 内容が読み込まれた時に呼び出される。
# on_quit とか要るか？
# on_idle
class Mode
  attr_accessor :keymap, :on_change, :on_load

  # 初期化メソッド
  def initialize(name)
    @name = name
    @keymap = Keymap.new

    @on_change = nil
    @on_load = nil
  end

  def name
    @name
  end

  def inspect
    "#<Mode #{@name}>"
  end
end

# 基本モード。Mode オブジェクトの初期化時に使っているので
# グローバル変数でなければならない。
$fundamental_mode = Mode.new("Fundamental")

# バッファーを表すクラス。
# TextView を作る時にはかならず Buffer クラスのオブジェクトを
# 対応付けなければいけない。
class Buffer < Gtk::TextBuffer
  attr_accessor :filename, :encoding, :eol, :buffer_name
  attr_accessor :insert_recorder_id, :delete_recorder_id
  attr_accessor :undo_stack, :redo_stack
  attr_accessor :major_mode
  attr_reader :minor_modes
  @@tag_table = nil

  alias :mode= :major_mode=
  alias :mode :major_mode

  def initialize
    @major_mode = $fundamental_mode

    @minor_modes = []

    @read_only = false

    if @@tag_table
      p "sharing tag_table"
      p @@tag_table
      super(@@tag_table)
    else
      table = create_tag_table
      p "initializing tag_table"
      super(table)
#      create_tags
      @@tag_table = table
    end

    @encoding = ENCODING_AUTO_DETECT
    @eol = "\r\n"

    # insert-text は実際に挿入された後に呼ばる。
    # そうでないとタグを適用できない。
    signal_connect_after("insert-text") do |widget, iter, text, len|
      text.force_encoding("UTF-8")
      iter.backward_chars(text.size)
      iter2 = iter.dup 
      text.size.times do
#        iter2 = iter.dup 
        iter2.forward_char
        tag = chartype(iter.char)
        unless tag == "ordinary"
          apply_tag(tag, iter, iter2)
        end
        iter.forward_char
      end
    end
    signal_connect_after("changed") do
      if @major_mode and @major_mode.on_change
        p "changed"
        @major_mode.on_change.call
      end
    end
    # signal_connect_after("delete-range") do
    #   if @major_mode and @major_mode.on_change
    #     p "changed"
    #     @major_mode.on_change.call
    #   end
    # end

    # undo redo はあとでやる
  end

  def read_only?
    return @read_only
  end

  def read_only=(bool)
    raise unless bool == true or bool == false
    return @read_only = bool
  end

  # カーソル位置(insert マークの位置)のイテレータを返す
  def get_iter_at_cursor
    m = get_mark("insert")
    return get_iter_at_mark(m)
  end

  # mark マークの位置のイテレータを返す
  def get_iter_at_mark(m)
    m = get_mark(m) if m.is_a? String
    super(m)
  end

  # メジャーモードのキーマップ
  def local_keymap
    return @major_mode.keymap
  end

  # バッファーの改行コードを変更する
  def set_eol(str)
    # 初期設定なら変更フラグを立てない
    @eol = str
  end

  # バッファーの保存時に使われる
  # ファイルエンコーディングを返す
  def set_encoding(enc)
    @encoding = enc
  end

  # タグテーブルを作って返す
  # すべてのバッファで同じタグテーブルを使うため、
  # 一度しか呼び出されない
  def create_tag_table
    # 初期化前にはプロパティの参照が出来なかった
    # if self.tag_table
    #   raise "this Buffer object already has a tag table"
    # end

    table = TextTagTable.new
    ordinary = TextTag.new("ordinary")
    ordinary.font = "MS Gothic"
    cp932 = TextTag.new("cp932")
    cp932.font = "Meiryo"
    cp932.foreground = CP932_FOREGROUND
    cp932.background = 'gray'
    unicode = TextTag.new("unicode")
    unicode.foreground = UNICODE_FOREGROUND
    unicode.background = 'gray'
    unicode.font = 'MS Gothic, BatangChe, Meiryo, Gautami, DokChampa, Sylfaen, Kartika'
    output = TextTag.new("output")
#    output.foreground = "#007700"
    output.foreground = "limegreen"
    output.font = 'MS Gothic'
    prompt = TextTag.new("prompt")
#    prompt.foreground = "darkblue"
    prompt.foreground = "skyblue"
    prompt.font = "Consolas, Meiryo"

    comment = TextTag.new("comment")
    comment.foreground = "#CC4444"
    literal = TextTag.new("literal")
    literal.foreground = "#BB6644"
    keyword = TextTag.new("keyword")
    keyword.foreground = "#CC55CC"
    green = TextTag.new("green")
    green.foreground = "#009900"
    gold = TextTag.new("gold")
    gold.foreground = "#BBBB00"
    skyblue = TextTag.new("skyblue")
    skyblue.foreground = "skyblue"

    highlight = TextTag.new("highlight")
    highlight.foreground = 'black'
    highlight.background = 'pink'

    table.add ordinary
    table.add cp932
    table.add unicode
    table.add output
    table.add prompt

    table.add comment
    table.add literal
    table.add keyword
    table.add green
    table.add gold
    table.add skyblue

    table.add highlight

    return table
  end
end

# 自動選択
ENCODING_AUTO_DETECT = 0
# Windows のShift_JIS
ENCODING_CP932 = 1
# MacJapanese
ENCODING_MACJAPANESE = 2
ENCODING_EUC_JP = 3
ENCODING_UTF8_NOBOM = 4
ENCODING_UTF8_BOM = 5

# アプリケーションメインウィンドウ
class MainWindow < Window
  # 修飾キーの一覧。
  # これらはキーコマンドとしては認識しない。
  MODIFIER_KEYS = [Gdk::Keyval::GDK_KEY_Shift_L,
                   Gdk::Keyval::GDK_KEY_Shift_R,
                   Gdk::Keyval::GDK_KEY_Control_L,
                   Gdk::Keyval::GDK_KEY_Control_R,
                   Gdk::Keyval::GDK_KEY_Meta_L,
                   Gdk::Keyval::GDK_KEY_Meta_R,
                   Gdk::Keyval::GDK_KEY_Alt_L,
                   Gdk::Keyval::GDK_KEY_Alt_R]

  # 初期化時にメニュー項目のラベルを保存する
  def _(label)
    @toplevel_menu_items << label
    return label
  end

  # 長すぎる初期化メソッド
  def initialize
    @major_mode_list = {}
    @major_mode_list['fundamental_mode'] = $fundamental_mode

    # メジャーモードの初期化 -----------------------------
    eval("load './ruby_mode.rb'")
    eval("extend RubyMode")
    $ruby_mode = create_ruby_mode
    @major_mode_list['ruby_mode'] = $ruby_mode

    eval("load './file_manager.rb'")
    eval("extend FileManagerMode")
    @major_mode_list['file_manager_mode'] = create_file_manager_mode

    eval("load './buffer_menu_mode.rb'")
    extend BufferMenuMode
    @major_mode_list['buffer_menu_mode'] = create_buffer_menu_mode

    eval("load './grep.rb'")
    extend GrepMode
    @major_mode_list['grep_mode'] = create_grep_mode

    eval("load './isearch.rb'")
    extend ISearchMode
    @major_mode_list['isearch'] = create_isearch_mode
    # マイナーモードだけど・・・

    # ----------------------------------------------------

    @buffers = []

    @toplevel_menu_items = []

    @eval_binding = binding

    # {[[keyval, mod]... ]=>proc], ...} 
    @global_keymap = Keymap.new # []
    @global_keymap.define_key("<space>", :self_insert_command)
    for i in 0x21..0x7e
      if i.chr =~ /^[A-Za-z0-9]$/
        @global_keymap.define_key(i.chr, :self_insert_command)
      else
        @global_keymap.define_key(ASCII2NAME[i.chr], :self_insert_command)
      end
    end

    @timeout_tags = []

    super

#    error_message(@major_mode_list.inspect)
    

#    Drag.dest_set(self, Drag::DEST_DEFAULT_MOTION |# Drag::DEST_DEFAULT_DROP |
#                       Drag::DEST_DEFAULT_HIGHLIGHT,
#                       [["text/uri-list", Drag::TARGET_OTHER_APP, 12345]], 
#                       Gdk::DragContext::ACTION_COPY|Gdk::DragContext::ACTION_MOVE)

    atom = Gdk::Atom.intern("CLIPBOARD", true)
    if atom == Gdk::Atom::NONE
      raise "CLIPBOARD"
    end
    @clipboard = Clipboard.get(atom)
    @uimanager = UIManager.new
    @uimanager.add_ui("textview_ui.xml")

    @global_accel_group = AccelGroup.new # ???残すか？
    self.add_accel_group @uimanager.accel_group


    act_group = ActionGroup.new("foo")
    # [[name, stock_id, label, accelerator, tooltip, proc, default], ... ]
    act_group.add_toggle_actions \
    [
     ["StatusBarAction", nil, "ステータスバー(_S)", nil, nil, proc {|group, action| action.active? ? @status_bar_hbox.show : @status_bar_hbox.hide }, true],
     ["CharInfoAction", nil, "文字情報", nil, nil, proc { |group, action|
        if action.active?
          @character_label.show
          @charinfo_label.show
        else
          @character_label.hide
          @charinfo_label.hide
        end
        }, false],
     ["ColorCodeAction", nil, "機種依存文字を色分け", nil, nil, proc { |group, action| if action.active? then set_colorcode(true) else set_colorcode(false) end }, false],
     ["WrapAction", nil, "右端で折り返す(_W)", nil, nil, proc {|group, action| set_wrap(action.active?) }, true],
     ["ViewModeAction", nil, "閲覧モード(_V)", "Escape", nil, proc {|group, action|
        toggle_view_mode(action.active?)
      }, false],
    ]
    act_group.add_radio_actions \
    [
     ["FixedAction", nil, "等幅フォント", nil, nil, 1],
     ["ProportionalAction", nil, "プロポーショナルフォント", nil, nil, 2],
    ] do |action, current|
      case current.name
      when "FixedAction"
        set_font("fixed")
      when "ProportionalAction"
        set_font("proportional")
      end
    end
    # [[name, stock_id, label, accelerator, tooltip, proc], ... ]
    act_group.add_actions \
    [
     ["FileMenuAction", nil, _("ファイル(_F)"), "", nil, proc { on_file_menu_open }],
     ["NewAction", Stock::NEW, "新規(_N)", "", nil, proc { new_file }],
     ["OpenAction", Stock::OPEN, "開く(_O)...", "", nil, proc { open_file }],
     ["OpenRecentAction", nil, "最近使ったファイル(_U)", "", nil, nil],
     ["SameDirAction", nil, "同じフォルダのファイル(_F)", "", nil, nil],
     ["CloseAction", Stock::CLOSE, "閉じる(_C)", "", nil, proc { close }],
     ["SaveAction", Stock::SAVE, "上書き保存(_S)", "", nil, proc { save_file }],
     ["SaveAsAction", Stock::SAVE_AS, "名前を付けて保存(_A)...", "", nil, proc { save_as }],
     ["RevertAction", Stock::REVERT_TO_SAVED, "読み直し(_R)", "", nil, proc { revert }],
     ["RevertWithEncodingAction", Stock::REVERT_TO_SAVED, "文字コードを指定して読み直し(_E)", "", nil, proc { open_revert_dialog }],
     ["QuitAction", Stock::QUIT, nil, "", nil, proc { quit }],
     ["EditMenuAction", nil, _("編集(_E)"), "", nil, proc { on_edit_menu_open } ],
     ["UndoAction", Stock::UNDO, "元に戻す(_U)", "", nil, proc { undo }],
     ["RedoAction", Stock::REDO, "やり直し(_D)", "", nil, proc { _redo }],
     ["CutAction", Stock::CUT, "切り取り(_T)", "", nil, proc { @buffer.cut_clipboard(@clipboard, true) }], # i don't understand what the second argument means. default_editable
     ["CopyAction", Stock::COPY, "コピー(_C)", "", nil, proc { @buffer.copy_clipboard(@clipboard) }],
     ["PasteAction", Stock::PASTE, "貼り付け(_P)", "", nil, proc { @buffer.paste_clipboard(@clipboard, nil, true) }],
     ["DeleteAction", Stock::DELETE, "削除(_L)", "", nil, proc { @buffer.delete_selection(true, true) }], #"Delete"
     ["FindAction", Stock::FIND, "検索(_F)...", "", nil, proc { open_find_dialog }],
     ["FindNextAction", nil, "次を検索(_N)", "", nil, proc { find_next }],
     ["ReplaceAction", Stock::FIND_AND_REPLACE, "置換(_R)...", "", nil, proc { open_replace_dialog }],
     ["GotoLineAction", Stock::JUMP_TO, "行へ移動(_G)", "", nil, proc { open_goto_line_dialog }],
     ["SelectAllAction", nil, "すべて選択(_A)", "", nil, proc { select_all}],
     ["FormatMenuAction", nil, _("書式(_O)"), "", nil, proc { on_format_menu_open }],
     ["ViewMenuAction", nil, _("表示(_V)"), "", nil, proc { on_view_menu_open } ],
     ["ZoomInAction", Stock::ZOOM_IN, "拡大(_I)", "", nil, proc {
        next if @current_point >= 14
        @current_point += 2
        apply_font_size
      }],
     ["ZoomOutAction", Stock::ZOOM_OUT, "縮小(_O)", "", nil, proc {
        next if @current_point <= 10
        @current_point -= 2
        apply_font_size
      }],
     ["ResetAction", Stock::ZOOM_100, "リセット(_R)", "", nil, proc {
        next if @current_point == 12
        @current_point = 12
        apply_font_size
      }],
     ["BuffersMenuAction", nil, _("バッファー(_B)"), "", nil, nil],
     ["MiscMenuAction", nil, _("その他(_M)"), "", nil, nil ],
     ["EvalAction", nil, "式を評価(_E)", "", nil, proc { eval_selection_or_line }],
     ["EvalPrintAction", nil, "式を評価して挿入(_P)", "", nil, proc { eval_print_selection_or_line } ],
     ["DeleteOutputAction", nil, "出力を削除(_D)", "", nil, proc { delete_all_output }],
     ["RestartAction", nil, "再起動(_R)", "", nil, proc { restart }],
     ["HelpMenuAction", nil, _("ヘルプ(_H)")],
     ["VersionAction", Stock::ABOUT, "バージョン情報(_A)", "", nil, proc { version }],
    ]
    act_group.add_actions\
    [
     ["CP932Action", nil, enc2str(ENCODING_CP932).gsub(/_/, "__"), nil, nil, proc { set_encoding(ENCODING_CP932) }],
     ["MacJapaneseAction", nil, enc2str(ENCODING_MACJAPANESE).gsub(/_/, "__"), nil, nil, proc { set_encoding(ENCODING_MACJAPANESE) }],
     ["EUC-JPAction", nil, enc2str(ENCODING_EUC_JP).gsub(/_/, "__"), nil, nil, proc { set_encoding(ENCODING_EUC_JP) }],
     ["UTF8_NOBOMAction", nil, enc2str(ENCODING_UTF8_NOBOM).gsub(/_/, "__"), nil, nil, proc { set_encoding(ENCODING_UTF8_NOBOM) }],
     ["UTF8_BOMAction", nil, enc2str(ENCODING_UTF8_BOM).gsub(/_/, "__"), nil, nil, proc { set_encoding(ENCODING_UTF8_BOM) }],
    ]
    act_group.add_actions\
    [
     ["CRLFAction", nil, "CR+LF", nil, nil, proc { set_eol("\r\n") }],
     ["CRAction", nil, "CR", nil, nil, proc { set_eol("\r") }],
     ["LFAction", nil, "LF", nil, nil, proc { set_eol("\n") }],
    ]
    @uimanager.insert_action_group(act_group, 0)
    @action_group = act_group

    ag = @global_accel_group
#    ag = AccelGroup.new
    # ag.connect(Gdk::Keyval::GDK_E, Gdk::Window::CONTROL_MASK,
    #            Gtk::ACCEL_VISIBLE) {
    #   open_eval_dialog
    # }
    ag.connect(Gdk::Keyval::GDK_J, Gdk::Window::CONTROL_MASK,
               Gtk::ACCEL_VISIBLE) {
      eval_print_selection_or_line
    }
    ag.connect(Gdk::Keyval::GDK_BackSpace, Gdk::Window::CONTROL_MASK | Gdk::Window::MOD1_MASK,
               Gtk::ACCEL_VISIBLE) {
      restart
    }
#    ag.connect(Gdk::Keyval::GDK_E, Gdk::Window::CONTROL_MASK,
#               Gtk::ACCEL_VISIBLE) {
#      eval_selection_or_line
#    }
#    add_accel_group(ag)

    @view_mode_accel_group = AccelGroup.new
    @view_mode_accel_group.connect(Gdk::Keyval::GDK_J, 0, ACCEL_VISIBLE) {
      @textview.signal_emit("move-cursor", MOVEMENT_DISPLAY_LINES, 1, false)
    }
    @view_mode_accel_group.connect(Gdk::Keyval::GDK_K, 0, ACCEL_VISIBLE) {
      @textview.signal_emit("move-cursor", MOVEMENT_DISPLAY_LINES, -1, false)
    }
    @view_mode_accel_group.connect(Gdk::Keyval::GDK_space, 0, ACCEL_VISIBLE) {
      @textview.signal_emit("move-cursor", MOVEMENT_PAGES, 1, false)
    }
    @view_mode_accel_group.connect(Gdk::Keyval::GDK_F, 0, ACCEL_VISIBLE) {
      @textview.signal_emit("move-cursor", MOVEMENT_PAGES, 1, false)
    }
    @view_mode_accel_group.connect(Gdk::Keyval::GDK_B, 0, ACCEL_VISIBLE) {
      @textview.signal_emit("move-cursor", MOVEMENT_PAGES, -1, false)
    }
    @view_mode_accel_group.connect(Gdk::Keyval::GDK_G, Gdk::Window::SHIFT_MASK, ACCEL_VISIBLE) {
      @textview.signal_emit("move-cursor", MOVEMENT_BUFFER_ENDS, 1, false)
    }
    @view_mode_accel_group.connect(Gdk::Keyval::GDK_G, 0, ACCEL_VISIBLE) {
      @textview.signal_emit("move-cursor", MOVEMENT_BUFFER_ENDS, -1, false)
    }
    @view_mode_accel_group.connect(Gdk::Keyval::GDK_slash, 0, ACCEL_VISIBLE) {
      open_find_dialog
    }
    @view_mode_accel_group.connect(Gdk::Keyval::GDK_N, 0, ACCEL_VISIBLE) {
      find_next
    }
    @view_mode_accel_group.connect(Gdk::Keyval::GDK_N, Gdk::Window::SHIFT_MASK, ACCEL_VISIBLE) {
      # find_prev とかまだなかった
    }
#    @view_mode_accel_group.connect(Gdk::Keyval::GDK_Q, 0, ACCEL_VISIBLE) {
#      toggle_view_mode(false) # 編集モードへ
#    }

    create_widgets
    layout_widgets
#    @buffer.create_tags
    connect_signals

    # デフォルトのエンコーディングと改行コードを設定する
    set_encoding(ENCODING_UTF8_BOM, true)
    set_eol("\r\n", true)
    


    update_status_bar

#    p Drag.dest_add_uri_targets(@textview)
   Drag.dest_set(@status_bar_hbox, Drag::DEST_DEFAULT_ALL,
                 [["text/uri-list", Drag::TARGET_OTHER_APP, 9999]], 
                 Gdk::DragContext::ACTION_COPY|Gdk::DragContext::ACTION_MOVE)
#    Drag.dest_set_proxy(@textview, selfl.window, Gdk::DragContext::PROTO_WIN32_DROPFILES, false)
    # @status_bar_hbox.signal_connect_after("drag-data-received") do |w, dc, x, y, selectiondata, info, time|
    #   puts "drag-data-received"
    #   if selectiondata.data.size >= 0 and selectiondata.format == 8
    #     p dc.action
    #     dc.targets.each do |target, i|
    #       p target.name
    #       if target.name == "text/uri-list"
    #         filename, hostname =  GLib.filename_from_uri(selectiondata.uris[0])
    #         filename.force_encoding("UTF-8")
    #         load_file(filename)
    #       end
    #     end
#        Drag.finish(dc, true, false, time)
      # end
#      Drag.finish(dc, false, false, time)
    # end
#    @textview.signal_connect("drag-drop") do |w, dc, x, y, time|
#      p dc.targets
#      p 'drag-drop'
#      Gtk::Drag.get_data(w, dc, dc.targets[0], time)
#      dc.drop_finish(true, time)
#    end
#    Drag.dest_unset(@textview)
#    Drag.source_unset(@textview)

    @current_point = 12
    @textview.modify_style(RcStyle.new)

#    load_file("test.txt")
    update_title

    if ENV['HOME']
      @home_dir = ENV['HOME']
    elsif ENV['APPDATA']
      @home_dir = ENV['APPDATA']
    else
      raise "どこに設定ファイルがあるのかわかりません"
    end
    dir = @home_dir
    dir += File::SEPARATOR
    dir += ".namopad"
    @dot_namopad = dir

    setup_global_keybind

    set_colorcode(false)

    self.icon = Gdk::Pixbuf.new("favicon.ico")

    set_emacs_mode(true)
    load_dot_namopad

    @textview.grab_focus

    @mb_lock = false

    @windows = [@textview, @minibuffer_view]

    @auto_mode_list = [] # [[/\.ext$/, $mode], ...]
    @auto_mode_list << [/\.rb$/, $ruby_mode]
    @auto_mode_list << [/\.namopad/, $ruby_mode]
  end
  # -- end of initialize()

  def self_insert_command
    @buffer.insert_at_cursor(@event.keyval.chr)
  end

  # システムのコマンドを実行する
  def shell_command
    prompt("Shell command: ") do |cmd|
      output = `#{cmd}`
      buf = get_buffer("*Shell Command Output*") 
      buf ||= create_new_buffer("*Shell Command Output*")
      buf.insert(buf.end_iter, output.encode("UTF-8"))
      switch_to_buffer(buf)
    end
  end

  # バッファーの 0 から数えて num 番目の行を文字列で返す
  def get_line(num)
    return nil if num < 0 or num >= @buffer.line_count
    i = @buffer.start_iter
    i.line = num
    j = i.dup
    j.forward_to_line_end unless j.ends_line?
    return @buffer.get_slice(i, j)
  end

  # ウィンドウ間を移動する
  # 今は、メインウィンドウとミニバッファーウィンドウの間だけ。
  def other_window
    found_p = false
    @windows.each do |w|
      next if w == @textview # dont grab self
      next if w == @minibuffer_view and not @mb_lock
      found_p = true
      w.grab_focus
    end
    found_p or (beep;info("ミニバッファーは非アクティブだよ"))
    return 
  end

  # C-<space> に割り当てられることを想定されている。
  # カレントバッファーでカーソル位置をマークする。
  def set_mark
    iter = @buffer.get_iter_at_cursor
    @buffer.move_mark("mark", iter)
    message("Mark set")
  end

  # ポイントとマークを交換する
  def exchange_point_and_mark
    i1 = @buffer.get_iter_at_cursor
    i2 = @buffer.get_iter_at_mark( @buffer.get_mark("mark") )
    @buffer.move_mark("insert", i2)
    @buffer.move_mark("selection_bound", i2)
    @buffer.move_mark("mark", i1)
    scroll_cursor_onscreen
  end

  # スクロールアップ＝ページダウン
  def scroll_up
    @textview.signal_emit("move-cursor", MOVEMENT_PAGES, 1, false)
  end

  # スクロールダウン＝ページアップ
  def scroll_down
    @textview.signal_emit("move-cursor", MOVEMENT_PAGES, -1, false)
  end

  # カーソル位置に文字列を挿入する
  def insert(str)
    @textview.insert_at_cursor(str)
    # scroll_cursor_onscreen
  end

  # クリップボードにリージョンをカットする
  # キルリングも実装しなくちゃいけない。
  def kill_region
    # selection_bound を mark に移動して cut!
    iter = @buffer.get_iter_at_mark( @buffer.get_mark("mark") )
    @buffer.move_mark("selection_bound", iter)
    @buffer.cut_clipboard(@clipboard, true)
  end

  def copy_region
    # マーク位置からカーソル位置までコピーする
    iter = @buffer.get_iter_at_mark( @buffer.get_mark("mark") )
    @buffer.move_mark("selection_bound", iter)
    @buffer.copy_clipboard(@clipboard)

    # 選択状態を解除する
    cursor = @buffer.get_iter_at_mark( @buffer.get_mark("insert") )
    @buffer.move_mark("selection_bound", cursor)

    message("コピーしました")
  end
  
  # リージョンの文字列を得る。
  def get_region
    iter = @buffer.get_iter_at_mark( @buffer.get_mark("mark") )
    iter2 = @buffer.get_iter_at_mark( @buffer.get_mark("insert") )
    return @buffer.get_slice(iter, iter2)
  end

  # リージョンを Ruby の式として評価する
  def eval_region
    code = get_region
    str = eval_inspect(code)
    if str.size > 80
      str = str[0..77] + "..."
    end
    message("⇒ " + str)
  end

  # その地点をマークして、貼り付け。
  # キルリング（ｒｙ
  def yank
    set_mark
    @buffer.paste_clipboard(@clipboard, nil, true)
  end

  def emacs_mode?
    return @uimanager.get_widget("ui/menubar/MiscMenu/EmacsMode").active?
  end

  # Emacs モードに入る。
  # 自前のキーハンドラが有効になり、
  # メニューバーのアクセラレーターが無効になる
  def set_emacs_mode(on_p)
    
    if on_p
      # ミニバッファーを表示する

      # メニューバーのショートカットキーを無効にする
      remove_accel_group @uimanager.accel_group
      @action_group.actions.each do |act|
        if @toplevel_menu_items.include?(act.label)
          act.label = act.label.sub(/\(_.\)/, "")
        end
      end
      # キー入力ハンドラーを接続する
      keybuffer = []
      @key_handler_id = @textview.signal_connect("key-press-event") do |w, e|
        @event = e
        @textview = w
        @buffer = w.buffer
        next key_handler(w, e, keybuffer)
      end
    else
      # ミニバッファーを隠す

      # メニューバーのショートカットキーを有効にする
      add_accel_group @uimanager.accel_group
      @action_group.actions.each do |act|
        label = act.label
        if label !~ /\)$/
          @toplevel_menu_items.each do |orig|
            act.label = orig if orig =~ /^#{label}\(_.\)$/
          end
        end
      end
      # キー入力ハンドラーを切断する
      @textview.signal_handler_disconnect(@key_handler_id) if @key_handler_id
    end
  end

  # マウスボタンを修飾キーとして使うモード
  def set_thinkpad_mod(on_p)
    if on_p
      self.events |= Gdk::Event::BUTTON_PRESS_MASK
      @button_ignore_id1 = @textview.signal_connect("button-press-event") do
        true
      end
      @button_ignore_id2 = @minibuffer_view.signal_connect("button-press-event") do
        true
      end
      @thinkpad_mod = true
    else
      return unless @button_ignore_id1
      @textview.signal_handler_disconnect(@button_ignore_id1)
      @minibuffer_view.signal_handler_disconnect(@button_ignore_id2)
      @thinkpad_mod = false
    end
  end

  # シンボルあるいは Proc を実行する
  def do_execute_command(cmd)
    message("DEBUG: #{cmd.inspect}") if @key_debug
    if cmd.is_a? Symbol
      unless self.methods.include? cmd
        beep
        message("#{cmd.to_s} という名前のメソッドは存在しません")
        return
      end
      @buffer.begin_user_action {
        begin
          self.method(cmd).call
        rescue Exception=>error
          text = sprintf("%s: %s\n%s\n",
                         error.class,
                         error.message,
                         error.backtrace.join("\n"))
          message(text)
        end
      }
    elsif cmd.is_a? Proc
      @buffer.begin_user_action {
        cmd.call
      }
    else 
      raise 
    end
  end

  # Array keybuffer は破壊的に変更する
  def key_handler(w, e, keybuffer)
    # ミニバッファーはとりあえず特別あつかい
    if @minibuffer == @buffer and @minibuffer_key_handler and @minibuffer_key_handler.call(w, e)
      return true
    end
    # コントロールと Alt 以外は無視する
    state = e.state & (Gdk::Window::CONTROL_MASK|Gdk::Window::MOD1_MASK)
    if @thinkpad_mod
      state |= Gdk::Window::MOD1_MASK if e.state & Gdk::Window::BUTTON1_MASK != 0
      state |= Gdk::Window::MOD1_MASK if e.state & Gdk::Window::BUTTON3_MASK != 0
    end
    keyval = e.keyval

    return false if MODIFIER_KEYS.include? keyval
    # Alt+` で漢字キーがくるけど voidsymbol!
    if keyval == Gdk::Keyval::GDK_VoidSymbol 
#      info("漢字キーっぽい")
      return false 
    end

    # エスケープが来たら、次のキーのメタ化する
    if keyval == Gdk::Keyval::GDK_Escape
      if keybuffer[-1] and keybuffer[-1][0] == Gdk::Keyval::GDK_Escape
        keybuffer.clear
        Gdk.beep
        return true
      end
      keybuffer << [keyval, state]
      msg = keybuffer.map{|key| key2str(*key)}.join(" ") + "-"
      message(msg)
      return true
    elsif keybuffer[-1] and keybuffer[-1][0] == Gdk::Keyval::GDK_Escape
      keybuffer.pop
      state = state |  Gdk::Window::MOD1_MASK
    end
    
    if state == Gdk::Window::CONTROL_MASK and
        key2str(keyval, state) =~ /C-([xcv])/
      key = $1
      # コピペ？
      i1, i2, selected_p = @buffer.selection_bounds
      if selected_p
        case key
        when "c"
          @buffer.copy_clipboard(@clipboard)
        when "x"
          @buffer.cut_clipboard(@clipboard, true)
        when "v"
          @buffer.paste_clipboard(@clipboard, nil, true)
        end
        return true
      end
    end

    minor_mode_keymaps = @buffer.minor_modes.map {|m| m.keymap}
    (minor_mode_keymaps + [@buffer.major_mode.keymap, @global_keymap]).each do |keymap|
      sequence = keybuffer + [[keyval, state]]
      rv = keymap.lookup(sequence)
#      puts "#{keymap.inspect}, #{sequence.inspect}, #{rv.inspect}"
      case rv 
      when true				# 部分マッチ
        keybuffer << [keyval, state]

        msg = keybuffer.map{|key| key2str(*key)}.join(" ") + "-"
        info(msg)

        return true
      when nil
        next
      else				# 完全マッチ
        do_execute_command(rv)
        keybuffer.clear
        return true
      end
    end

    # キーバインドが見つからない
    if not keybuffer.empty?
      # キーシークエンスが失敗した
      str = (keybuffer + [[keyval, state]]).map{|key| key2str(*key)}.join(" ")
      info("#{str} is undefined.")
      keybuffer.clear

      return true
    else
      if @buffer.read_only? and (0x020..0x7e).include? keyval  # ASCII printable characters
        message("このバッファは変更できません")
        beep
        return true
      end
      keybuffer.clear
      return false
    end
    raise "不到達"
  end

  # @key_debug 変数のブール値をオンオフする
  def toggle_key_debug
    @key_debug = !@key_debug
    message("KEY DEBUG = #{@key_debug}")
  end

  def describe_key
    clear_minibuffer
    @minibuffer_view.grab_focus
    buf = @minibuffer
    buf.insert(buf.start_iter, "Describe key: ", "prompt")
    
    str = nil
    id = @minibuffer_view.signal_connect("key-press-event") do |w, e|
      str = key2str(e.keyval, e.state)
      info(str)
      @minibuffer_view.signal_handler_disconnect(id)
      clear_minibuffer
      @textview.grab_focus
      true
    end
  end

  # @global_keymap にキーバインドを追加する
  # C- <Control>
  # M- <Alt>
  def global_set_key(keystr, sym)
    define_key(@global_keymap, keystr, sym)
  end

  def define_key(keymap, keystr, sym)
    if sym.is_a? Symbol
      raise "そんなメソッドないです" unless self.methods.include? sym
    end
    unless sym.is_a? Symbol or sym.is_a? Proc
      raise "Symbol か Proc にしてください"
    end

    keymap.define_key(keystr, sym)

    return true
  end

  # For convenience
  def global_unset_key(keystr)
    @global_keymap.undefine_key(keystr)
  end

  # n 文字進む。
  def forward_char(n = 1)
    return if n == 0 # 0 を gtk に渡すとクラッシュする
    # MOVEMENT_LOGICAL_POSITIONS だとなぜかバッファの最後に移動できない
    @textview.move_cursor(MOVEMENT_VISUAL_POSITIONS, n, false)
  end

  # n 文字戻る。
  def backward_char(n = 1)
    return if n == 0
    @textview.move_cursor(MOVEMENT_VISUAL_POSITIONS, -n, false)
  end

  # カーソルの右にある文字を削除する
  def delete_char(n = 1)
    return if n == 0
    @textview.signal_emit("delete-from-cursor", DELETE_CHARS, n)
  end

  # １行上に行く
  def previous_line(n = 1)
    return if n == 0
    i = @buffer.get_iter_at_cursor
    if i.line == 0 # 行頭に移動することをしない
      beep
      return 
    end
    @textview.signal_emit("move-cursor", MOVEMENT_DISPLAY_LINES, -n, false)
  end

  # n 行下に進む
  def next_line(n = 1)
    return if n == 0
    @textview.signal_emit("move-cursor", MOVEMENT_DISPLAY_LINES, n, false)
  end

  # カーソル位置で改行するが、カーソルはその位置にとどまる
  def open_line
    iter = @buffer.get_iter_at_cursor
    @buffer.insert(iter, "\n")
    backward_char
  end

  # 論理行頭に移動する。
  def move_beginning_of_line
    @textview.signal_emit("move-cursor", MOVEMENT_PARAGRAPH_ENDS, -1, false)
  end

  # 論理行末に移動する。
  def move_end_of_line
    @textview.signal_emit("move-cursor", MOVEMENT_PARAGRAPH_ENDS, 1, false)
  end

  # .namopad ファイルを読み込む
  def load_dot_namopad
    unless File.exist? @dot_namopad
      # touch it
      File.new(@dot_namopad, "wb").close
    end

    str = File.new(@dot_namopad, "rb").read
    begin
      eval(str, @eval_binding, @dot_namopad)
    rescue Exception=>error
      text = sprintf("%s: %s\n%s\n",
                     error.class,
                     error.message,
                     error.backtrace.join("\n"))
      errbuf = create_new_buffer("*.namopad Error*")
#      errbuf.major_mode = $fundamental_mode
      errbuf.text = text
      switch_to_buffer(errbuf)
    end
  end

  # 引数取ってるのに toggle ってのはおかしいな
  def toggle_view_mode(enable_p)
    if enable_p
      raise "なんかおかしい" unless @textview.cursor_visible?
      @textview.cursor_visible = false
      @textview.editable = false
      b = "<span background=\"black\" foreground=\"white\" font_weight=\"bold\">"
      e = "</span>"
      b = ""
      e = ""
      message("閲覧モード #{b} Esc #{e}: 編集モードへ #{b} j #{e}: １行下 #{b} k #{e}: １行上 #{b} space #{e}: １頁下 #{b} b #{e}:１頁上")
      # キーバインドをつっこむ
      self.add_accel_group(@view_mode_accel_group)
    else
      # 閲覧モードを抜ける
      raise "なんかおかしい" if @textview.cursor_visible?
      @textview.cursor_visible = true
      @textview.editable = true
      message("編集モード")
      self.remove_accel_group(@view_mode_accel_group)
      @textview.place_cursor_onscreen # カーソルを画面内に移動させる
    end
    update_title
  end

  # 現在の行の内容を文字列で返す
  def get_line_under_cursor
    point = @buffer.get_iter_at_cursor
    iter = @buffer.get_iter_at_line(point.line) # 行頭
    point.forward_to_line_end unless point.ends_line?
    str = @buffer.get_slice(iter, point) # 行の内容
    return str
  end

  # 選択された領域がある場合は、それを評価。
  # ない場合は、カーソルのある行を評価。
  def eval_selection_or_line
    start_iter, end_iter, selected_p = @buffer.selection_bounds
    if selected_p
      exp = @buffer.get_slice(start_iter, end_iter)
      text = eval_inspect(exp)
      message("⇒ " + text)
    else
      eval_line
    end
  end

  # 現在の行の内容を評価
  def eval_line
    exp = get_line_under_cursor
    return if exp.empty?
    text = eval_inspect(exp)
    message("⇒ " + text)
  end

  # フォントを変更する
  # GTK が不意に落ちるので使えない
  # type: "fixed" or "proportional"
  def set_font(type)
    t = @buffer.tag_table
    ordinary = t.lookup('ordinary')
    cp932 = t.lookup('cp932')
    unicode = t.lookup('unicode')
    output = t.lookup('output')

    case type
    when "fixed"
      ordinary.font = "MS Gothic"
      cp932.font = "MS Gothic"
      unicode.font = "MS Gothic, BatangChe, Meiryo, Gautami, DokChampa, Sylfaen, Kartika"
      output.font = "MS Gothic"
    when "proportional"
      ordinary.font = "Meiryo"
      cp932.font = "Meiryo"
      unicode.font = "Meiryo, BatangChe, Meiryo, Gautami, DokChampa, Sylfaen, Kartika"
      output.font = "Meiryo"
    end
  end

  # このあたりの Emacs 関数を移すか。未実装
  def line_beginning_position
  end

  # 未実装
  def line_end_position
  end

  # 未実装？？？何に使うんだ？
  def delete_region(p1, p2)
  end

  # カーソル位置から行末までをカットする
  # もとから行末にいる場合は改行文字を削除する（カットではない）
  # バッファー終端のために改行文字もない場合は音を鳴らすだけ
  def kill_line
    point = @buffer.get_mark("insert")
    iter = @buffer.get_iter_at_mark(point)
    line = get_line_under_cursor
    if iter.ends_line?
      if iter.char == "" # EOF
        beep
      else
        delete_char
      end
    else
      iter = @buffer.get_iter_at_offset (iter.offset + (line.size - iter.line_offset) )
      @buffer.move_mark("insert", iter)
      @buffer.cut_clipboard(@clipboard, true)
    end
  end

  # 再起動する。
  def restart
    $RESTART_FLAG = true
    if @buffer.filename
      $RESTART_FILENAME = @buffer.filename
    end 
    Gtk.main_quit
  end
    

  def eval_print_selection_or_line
    start_iter,  end_iter, selected_p = @buffer.selection_bounds
    if selected_p
      exp = @buffer.get_slice(start_iter, end_iter)
      @buffer.move_mark("insert", end_iter)
      # 選択領域の最後に移動して、選択を解除する
      do_eval_print(exp)
      iter = @buffer.get_iter_at_mark( @buffer.get_mark("insert") )
      @buffer.move_mark("selection_bound", iter)
    else
      eval_print_line
    end
  end

  def eval_print_line
    # その行を評価する。カーソールの前？？？
    # end } の最後で実行された場合は、
    # 対応するインデント量の if begin while for def ?
    # まで遡って領域を評価する。
#    insert = @buffer.get_iter_at_mark(@buffer.get_mark("insert"))
#    iter_a = @buffer.get_iter_at_line(insert.line)
#    exp = @buffer.get_slice(iter_a, insert)
    exp = get_line_under_cursor
    return if exp == ""

    do_eval_print(exp)
  end

  def delete_all_output
    iter = @buffer.start_iter
    i = 0 
    while i < @buffer.line_count # 作業中に変わりうる
      prev = iter.dup
      if i == @buffer.line_count-1
        iter = @buffer.end_iter
      else
        iter.line += 1
      end
      line = @buffer.get_slice(prev, iter)
      if line =~ /^⇒/
        @buffer.delete(prev, iter)
      else
        i += 1
      end
    end
  end

  def do_eval_print(exp)
    @buffer.begin_user_action {
      if @buffer.cursor_position == @buffer.end_iter.offset
        move_end_of_line
        @textview.insert_at_cursor("\n")
      end
      next_line
      line = get_line_under_cursor
      if line =~ /^⇒/
        move_beginning_of_line
        iter = @buffer.get_iter_at_mark(@buffer.get_mark("insert"))
        iter2 = iter.dup
        iter2.line = iter.line + 1
        @buffer.delete(iter, iter2)
      else
        move_beginning_of_line
      end
        
#      @textview.move_cursor(MOVEMENT_PARAGRAPH_ENDS, 1, 0)
#      insert = @buffer.get_iter_at_mark(@buffer.get_mark("insert"))
#      @buffer.insert(insert, "\n")
#      @buffer.move_mark("insert", insert)
#      @buffer.move_mark("selection_bound", insert)
      if exp[0] == "!"
        system(exp[1..-1])
        text = ""
      else
        text = eval_inspect(exp)
        text = "⇒ " + text + "\n"
      end
      insert = @buffer.get_iter_at_mark(@buffer.get_mark("insert"))
      @buffer.insert(insert, text, "output")
      @buffer.move_mark("selection_bound", insert)
      scroll_cursor_onscreen
    }
  end

  def system(str)
    str = eval("\"#{str}\"", @eval_binding) # 文字列中の埋め込み変数を展開 echo #{x} => echo 1
    str = str.encode("cp932")
    res = `#{str}`.encode("UTF-8")
    point = @buffer.get_iter_at_mark(@buffer.get_mark("insert"))
    @buffer.insert(point, res, "output")
    return true
  end

  def create_encoding_combobox
    c = ComboBox.new
    l = Label.new("文字エンコーディング:")
#    l.xalign =1
    c.append_text("自動選択")
    c.append_text("Shift_JIS (Windows)")
    c.append_text("Shift_JIS (Mac)")
    c.append_text("EUC-JP")
    c.append_text("UTF-8")
    c.append_text("UTF-8 with BOM")
    return c
  end

  def open_revert_dialog
    return unless @buffer.filename
    dialog = Dialog.new("文字コードを指定して読み直し", self, Dialog::DESTROY_WITH_PARENT)
#    dialog.vbox.pack_start(Label.new("“#{@buffer.filename}”:"))
    c = create_encoding_combobox
    c.signal_connect("key-press-event") do |w, event|
      if Gdk::Keyval.to_name(event.keyval) == "Return"
        dialog.response(1)
        true
      else
        false
      end
    end
    dialog.vbox.pack_start(c)

    guess = enc2str(auto_detect(File.new(@buffer.filename, "rb").read))
    c.remove_text(ENCODING_AUTO_DETECT)
    c.prepend_text("自動選択 - #{guess}")
    c.active = 0

    dialog.vbox.show_all

    dialog.add_buttons(["開く", 1],
                       ["キャンセル", RESPONSE_CANCEL])
    loop do
      res = dialog.run
      case res
      when 1
        #開く
        success_p = load_file(@buffer.filename, c.active)
        if success_p
          break
        else
          redo 
        end
      else
        break # cancel or delete
      end
    end
    dialog.destroy
    return
  end
  
  def eol2str(eol)
    return { "\r\n"=>"CR+LF", "\r" => "CR", "\n"=>"LF" }[eol]
  end

  def set_eol(eol, secretly = false)
    @textview.buffer.set_eol(eol)
    @EOL_label.text = eol2str(eol)
    @buffer.modified = true unless secretly
  end

  # 第２引数が true だとバッファーの modified? を変更しない
  def set_encoding(enc, secretly = false)
    @textview.buffer.set_encoding(enc)
    @encoding_label.text = enc2str(enc)
    @buffer.modified = true unless secretly
    set_eol("\r", secretly) if enc == ENCODING_MACJAPANESE
    set_eol("\n", secretly) if enc == ENCODING_EUC_JP
    set_eol("\r\n", secretly) if enc == ENCODING_CP932
    @undo_stack = []
    @redo_stack = []
  end

  def next_buffer
    if i = @buffers.index(@buffer)
      old_buf = @buffer.buffer_name
      if @buffer == @minibuffer
        message("ミニバッファーから呼ばないで＞＜")
        return
      end
      i += 1
      if i == @buffers.size
        i = 0 # 先頭に戻る
      end
      @buffer = @textview.buffer = @buffers[i]
      # info("#{old_buf} から #{@buffer.buffer_name} に移動したよ") 
    else
      @buffer = @textview.buffer = @buffers[0]
      # info("#{old_buf} から #{@buffer.buffer_name} に移動したよ")
    end
    update_title
    update_status_bar
  end

  def open_replace_dialog
    dialog  = Dialog.new("置換", self, Dialog::DESTROY_WITH_PARENT)
    hbox = HBox.new(false, 10)

    left_vbox = VBox.new(false, 5)

    find_hbox = HBox.new(false, 5)
    find_label = Label.new("検索する文字列:")
    find_entry = Entry.new
    find_entry.text = @search_term if @search_term
    find_hbox.pack_start(find_label, false)
    find_hbox.pack_start(find_entry, true)
    
    replace_hbox = HBox.new(false, 5)
    replace_label = Label.new("置換後の文字列:")
    replace_entry = Entry.new
    replace_entry.text = @replace_term if @replace_term
    replace_hbox.pack_start(replace_label, false)
    replace_hbox.pack_start(replace_entry, true)

    left_vbox.pack_start(find_hbox, false)
    left_vbox.pack_start(replace_hbox, false)
    hbox.pack_start(left_vbox)

    button_vbox = VBox.new(false, 10)
    find_next_button = Button.new("次を検索")
    find_next_button.signal_connect("clicked") {
      if find_entry.text == ""
        error_message("何も入ってないよ")
        next
      end
      @search_term = find_entry.text
      find_next
    }
    replace_button = Button.new("置換して次に")
    replace_button.signal_connect("clicked") {
      if find_entry.text == ""
        error_message("検索する文字列を入力してください")
      end
      @search_term = find_entry.text
      @replace_term = replace_entry.text
      # 1. 何も選択されてなかったら、次の検索語を選択する
      # 2. 検索語でないものが選択されていたら、次の検索語を選択する
      # 3. 検索語が選択されていたら、置換後の文字列で置換する
      iter1, iter2, selected_p = @buffer.selection_bounds
      if selected_p and @buffer.get_slice(iter1, iter2) == @search_term
        # 置換
        @buffer.begin_user_action {
          @buffer.delete(iter1, iter2)
          @buffer.insert(iter1, @replace_term) 
        }
      end
      find_next
    }
    replace_all_button = Button.new("全て置換")
    replace_all_button.signal_connect("clicked") {
      if find_entry.text == ""
        error_message("検索する文字列を入力してください")
      end
      @search_term = find_entry.text
      @replace_term = replace_entry.text

      str = @buffer.text
      st = Regexp.escape(@search_term)
      @buffer.begin_user_action do 
        @buffer.delete(@buffer.start_iter, @buffer.end_iter)
        @buffer.insert(@buffer.start_iter, str.gsub(/#{st}/, @replace_term))
      end

      @buffer.move_mark("insert", @buffer.start_iter)
      @buffer.move_mark("selection_bound", @buffer.start_iter)
    }
    cancel_button = Button.new("キャンセル")
    cancel_button.signal_connect("clicked") {
      dialog.response(RESPONSE_CANCEL)
    }
    button_vbox.pack_start(find_next_button)
    button_vbox.pack_start(replace_button)
    button_vbox.pack_start(replace_all_button)
    button_vbox.pack_start(cancel_button)

    hbox.pack_start(button_vbox)
    hbox.border_width = 5

    dialog.vbox.pack_start(hbox)

    hbox.show_all

    res = dialog.run
    # res は見ない
    dialog.destroy
    
  end

  def enc2str(enc)
    return ["Auto Detect",
    "Shift_JIS (Win)",
    "Shift_JIS (Mac)",
    "EUC-JP",
    "UTF-8",
    "UTF-8 with BOM"][enc]
  end

  # アンドゥーした操作をやり直す。
  # redo が予約語なのでこの名前。
  def _redo
    if @buffer.redo_stack.size == 0
      message("これ以上やり直せません。")
      Gdk.beep
      return 
    end
      

    @buffer.signal_handler_block(@insert_recorder_id)
    @buffer.signal_handler_block(@delete_recorder_id)

    a = @buffer.redo_stack.pop
    a.each do |h|
      case h['action']
      when "insert"
        iter = @buffer.get_iter_at_offset(h["offset"])
        @buffer.insert(iter, h["text"])
        iter2 = @buffer.get_iter_at_offset(h["offset"] + h["text"].size)
        @buffer.move_mark("selection_bound", iter2)
        @buffer.move_mark("insert", iter2)
        scroll_cursor_onscreen
      when "delete"
        iter1 = @buffer.get_iter_at_offset(h["offset"])
        iter2 = @buffer.get_iter_at_offset(h["offset"] + h["text"].size)
        @buffer.delete(iter1, iter2)
        iter = @buffer.get_iter_at_offset(h["offset"]) # iter1 再利用できるんじゃないか
        @buffer.move_mark("selection_bound", iter)
        @buffer.move_mark("insert", iter)
        scroll_cursor_onscreen
      end
    end
    @buffer.undo_stack.push a
    
    @buffer.signal_handler_unblock(@insert_recorder_id)
    @buffer.signal_handler_unblock(@delete_recorder_id)

    message("やり直し (あと #{@buffer.redo_stack.size} 回)")
  end

  def undo
    if @buffer.undo_stack.size == 0
      message("これ以上元に戻せません。")
      Gdk.beep
      return
    end

    @buffer.signal_handler_block(@buffer.insert_recorder_id)
    @buffer.signal_handler_block(@buffer.delete_recorder_id)

    a = @buffer.undo_stack.pop
    a.reverse.each do |h| # revert the actions in reverse order
      case h["action"]
      when "insert"
        # we are going to delete some text
        iter1 = @buffer.get_iter_at_offset(h["offset"])
        iter2 = @buffer.get_iter_at_offset(h["offset"] + h["text"].size)
        @buffer.delete(iter1, iter2)
        iter = @buffer.get_iter_at_offset(h["cursor_offset"])
        @buffer.move_mark("selection_bound", iter)
        @buffer.move_mark("insert", iter)
        scroll_cursor_onscreen
      when "delete"
        # we are going to insert text that has been deleted
        iter = @buffer.get_iter_at_offset(h["offset"])
        @buffer.insert(iter, h["text"])
        iter2 = @buffer.get_iter_at_offset(h["cursor_offset"])
        @buffer.move_mark("selection_bound", iter2)
        @buffer.move_mark("insert", iter2)
        scroll_cursor_onscreen
      end
    end
    @buffer.redo_stack.push a

    @buffer.signal_handler_unblock(@buffer.insert_recorder_id)
    @buffer.signal_handler_unblock(@buffer.delete_recorder_id)

    message("元に戻す (あと #{@buffer.undo_stack.size} 回)")

    @buffer.modified = false if @buffer.undo_stack.empty?
  end

  # カーソルより前にある検索語に一致する部分の
  # オフセットを返す [[n1, n2], [m1, m2]...]
  def get_offsets_forward(term)
    text = @buffer.text
    st = Regexp.escape(term)
    offsets = []
    pos = @buffer.cursor_position
    text.scan(/#{st}/) {|x|
      o = $~.offset(0)
      if o[0] >= pos
        offsets << o
      end
    }
    return offsets
  end

  # 次のマッチを探す
  def find_next
    unless @search_term
      open_find_dialog
      return
    end
    offsets = get_offsets_forward(@search_term)
    if offsets[0] == nil
      error_message("#{@search_term} が見つかりません。")
      return
    end
    o = offsets[0] 
    start_iter = @buffer.get_iter_at_offset(o[0])
    end_iter = @buffer.get_iter_at_offset(o[1])
    @buffer.move_mark("selection_bound", start_iter)
    @buffer.move_mark("insert", end_iter)
    scroll_cursor_onscreen
  end

  # do not confuse with Gtk::TextView#scroll_to_mark
  def scroll_cursor_onscreen
    # scroll so that the cursor is in the middle of the screen
    # and hscrollbar is on the left (if possible)
#    @textview.scroll_to_mark(@buffer.get_mark("insert"), 0.0, true, 1.0, 0.5)
    @textview.scroll_to_mark(@buffer.get_mark("insert"), 0.0, false, 0, 0)
  end

  def open_find_dialog
    dialog  = Dialog.new("検索", self, Dialog::DESTROY_WITH_PARENT, ["検索", 1], ["キャンセル", RESPONSE_CANCEL])
    dialog.default_response = 1
    hbox = HBox.new(false, 5)
    label = Label.new("検索する文字列:")
    hbox.pack_start(label, false)
    entry = Entry.new
    if @search_term
      entry.text = @search_term
    end
    hbox.pack_start(entry, true)
    entry.signal_connect("activate") {
      dialog.response(1)
    }
    dialog.vbox.pack_start(hbox, true)
    dialog.vbox.show_all
    hbox.border_width = 10
    while true
      res = dialog.run
      case res
      when 1
        redo if entry.text == ""
        @search_term = entry.text
        find_next
        break # break the while loop
      else
        # Cancel button was clicked, delete event has occured etc.
        # Basically, close the dialog.
        break
      end
    end
    dialog.destroy
  end

  # eval して Ruby インタープリタの出力を返す
  def eval_inspect(exp)
    raise unless @eval_binding
    begin
#      $stdout = buf = StringIO.new
      fn = @buffer.filename ? @buffer.filename : "<unknown>"
      rv = eval(exp, @eval_binding, fn)
      text = rv.inspect
    rescue Exception=>error
      text = sprintf("%s: %s\n%s",
                     error.class,
                     error.message,
                     error.backtrace.join("\n"))
    ensure
#      $stdout = STDOUT
    end
#    @textview.insert_at_cursor(buf.string)
    return text
  end

  def open_eval_dialog
    dialog  = Dialog.new("Eval", self, Dialog::DESTROY_WITH_PARENT, ["実行", 1], ["キャンセル", RESPONSE_CANCEL])
    dialog.default_response = 1
    hbox = HBox.new(false, 5)
    label = Label.new("eval:")
    hbox.pack_start(label, false)
    entry = Entry.new
    hbox.pack_start(entry, true)
    output = Label.new("")
    output.xalign = 0
#    output.wrap= true
    entry.signal_connect("activate") {
      dialog.response(1)
    }
    dialog.vbox.pack_start(hbox, true)
    dialog.vbox.pack_start(output, false)
    dialog.vbox.show_all
    hbox.border_width = 10
    while true
      res = dialog.run
      case res
      when 1
        redo if entry.text == ""
          begin
            rv = eval(entry.text)
            text = rv.inspect + "\n"
          rescue =>error
            text = sprintf("%s: %s\n%s\n",
                    error.class,
                    error.message,
                    error.backtrace.join("\n"))
          end
          # output.text = rv.inspect[0..20]
          @buffer.insert(@buffer.end_iter, text)
        redo
      else
        # Cancel button was clicked, delete event has occured etc.
        # Basically, close the dialog.
        break
      end
    end
    dialog.destroy
  end

  def open_goto_line_dialog
    dialog = Dialog.new("行へ移動",
               self,
               Dialog::DESTROY_WITH_PARENT,
               [ "移動", 1], ["キャンセル", RESPONSE_CANCEL])
    dialog.default_response = 1
    hbox = HBox.new(false, 5)
    label = Label.new("行番号:")
    hbox.pack_start(label, false)
    number_entry = Entry.new
    number_entry.signal_connect("activate") { # when Enter key is hit
      dialog.response(1)			# go to line
    }
    hbox.pack_start(number_entry, true)
    dialog.vbox.pack_start(hbox, true)
    dialog.vbox.show_all
    hbox.border_width = 10
    dialog.run do |res|
      begin
        case res
        when 1
          t = number_entry.text
          goto_line(t)
        when RESPONSE_CANCEL
          return
        end
      ensure
        dialog.destroy
      end
    end
  end

  def search_forward
    default = @search_term ? @search_term : ""
    prompt("Search forward: ", default) do |str|
      @search_term = str if str != ""
      iter = @buffer.get_iter_at_cursor
      start_iter, end_iter = iter.forward_search(str, TextIter::SEARCH_TEXT_ONLY, nil)
      unless start_iter
        beep
        message("Search failed \"#{str}\"")
        next
      end
      @buffer.place_cursor(start_iter)
      scroll_cursor_onscreen
    end
  end

  def search_backward
    default = @search_term ? @search_term : ""
    prompt("Search backward: ", default) do |str|
      @search_term = str if str != ""
      iter = @buffer.get_iter_at_cursor
      start_iter, end_iter = iter.backward_search(str, TextIter::SEARCH_TEXT_ONLY, nil)
      unless start_iter
        beep
        message("Search failed \"#{str}\"")
        next
      end
      @buffer.place_cursor(start_iter)
      scroll_cursor_onscreen
    end
  end

  def goto_line(number_str)
    unless number_str =~ /^[\d１２３４５６７８９０]+$/
      # "" が来た場合はバッファの最後に移動すべきか？
      error_message("数を入力してください。")
      return
    end
    # 全角数字半角化
    number_str = $&.tr("１２３４５６７８９０", "1234567890")
    number = number_str.to_i
    if number == 0
      error_message("行番号は 1 から始まります。")
      return
    end
    if number > @buffer.line_count
      error_message("指定した行番号は行の総数を超えています。")
      return
    end
    iter = @buffer.get_iter_at_line_offset(number - 1, 0)
    @buffer.move_mark("insert", iter)
    @buffer.move_mark("selection_bound", iter)
    scroll_cursor_onscreen
  end

  def set_colorcode(enabled_p)
    table = @buffer.tag_table
    ordinary = table.lookup('ordinary')
    cp932 = table.lookup('cp932')
    unicode = table.lookup('unicode')
    if enabled_p
      cp932.foreground=CP932_FOREGROUND
      cp932.background="gray"
      unicode.foreground=UNICODE_FOREGROUND
      unicode.background="gray"
    else
      cp932.foreground=nil
      cp932.background=nil
      unicode.foreground=nil
      unicode.background=nil
    end
  end

  def set_wrap(on_p)
    if on_p
      @textview.wrap_mode = TextTag::WRAP_CHAR
    else
      @textview.wrap_mode = TextTag::WRAP_NONE
    end
  end

  def on_format_menu_open
    zoomin = @uimanager.get_widget("ui/menubar/FormatMenu/ZoomIn")
    zoomout = @uimanager.get_widget("ui/menubar/FormatMenu/ZoomOut")
    reset = @uimanager.get_widget("ui/menubar/FormatMenu/Reset")
    zoomin.sensitive = (@current_point < 14)
    zoomout.sensitive = (@current_point > 10)
    reset.sensitive = (@current_point != 12)
  end

  def on_buffers_menu_open
    @buffers_menu.children.each do |child|
      @buffers_menu.remove(child)
    end

    @buffers.sort {|x, y| x.buffer_name <=> y.buffer_name}.each do |b|
      item = MenuItem.new(b.buffer_name, false).show
      item.signal_connect("activate") do 
        switch_to_buffer(b)
      end
      @buffers_menu.append(item)
    end
  end

  def on_view_menu_open
    charinfo = @uimanager.get_widget("ui/menubar/ViewMenu/CharInfo") # get the menuitem
    charinfo.sensitive = @status_bar_hbox.visible?
  end

  def textview_unfocus
    @encoding_button.grab_focus # TextView のフォーカスを外す＾＾；    
  end

  def on_file_menu_open
    save = @uimanager.get_widget("ui/menubar/FileMenu/Save")
    save.sensitive = (not @buffer.filename or @buffer.modified?)
    revert = @uimanager.get_widget("ui/menubar/FileMenu/Revert")
    revert_with_encoding = @uimanager.get_widget("ui/menubar/FileMenu/RevertWithEncoding")
    if @buffer.filename and @buffer.modified?
      revert.sensitive = true
    else
      revert.sensitive = false
    end
    if @buffer.filename
      revert_with_encoding.sensitive = true
    else
      revert_with_encoding.sensitive = false
    end

  end

  def do_revert
    load_file(@buffer.filename)
  end

  def revert
    return unless @buffer.filename # this shouldn't happend but...
    dialog = MessageDialog.new(self, Dialog::DESTROY_WITH_PARENT,
                               MessageDialog::QUESTION,
                               MessageDialog::BUTTONS_OK_CANCEL,
                               "変更内容をキャンセルしますか？")
    dialog.title = $APPLICATION_NAME
    dialog.run { |res|
      begin
        case res
        when Dialog::RESPONSE_OK
          do_revert
        when Dialog::RESPONSE_CANCEL
          return
        else
          p res
          raise "unknown response"
        end
      ensure
        dialog.destroy 
      end
    }
  end


  def version
    # or about dialog
    dialog = Dialog.new("#{$APPLICATION_NAME}のバージョン情報", self, Dialog::MODAL)
    dialog.vbox.spacing = 5
    dialog.add_button(Stock::OK, Dialog::RESPONSE_OK)
    dialog.vbox.pack_start(Image.new("favicon.ico"))
    date = nil
    if TIME_STAMP =~ /\d{4}-\d+-\d+/ # ＄＆でインデントがおかしくなる
      date = $& 
    end
    version_label = Label.new
    version_label.set_markup("<span font_size=\"14000\">#{$APPLICATION_NAME} #{date}版</span>")
    dialog.vbox.pack_start(version_label)
    dialog.vbox.pack_start(Label.new("(/ω＼*)ｷｬｯ"))
    dialog.show_all
    dialog.run do |res|
      dialog.destroy
    end
  end

  def select_all
    @buffer.move_mark("insert", @buffer.end_iter)
    @buffer.move_mark("selection_bound", @buffer.start_iter)
  end

  def on_edit_menu_open
    undo = @uimanager.get_widget("ui/menubar/EditMenu/Undo")
    undo.sensitive = (@buffer.undo_stack.size > 0)
    _redo = @uimanager.get_widget("ui/menubar/EditMenu/Redo")
    _redo.sensitive = (@buffer.redo_stack.size > 0)

    selected = @buffer.has_selection?
    cut = @uimanager.get_widget("ui/menubar/EditMenu/Cut")
    cut.sensitive = selected
    copy = @uimanager.get_widget("ui/menubar/EditMenu/Copy")
    copy.sensitive = selected
    paste = @uimanager.get_widget("ui/menubar/EditMenu/Paste")
    paste.sensitive = true # clipboard_has_text?
    delete = @uimanager.get_widget("ui/menubar/EditMenu/Delete")
    delete.sensitive = selected
  end

  # doesn't return true for text other application programs copied
  def clipboard_has_text?
    has_text = false
    @clipboard.request_text { |clipboard, text|
      #    @clipboard.request_rich_text(@buffer) { |clipboard, format, text|
      has_text = text ? true : false
    }
    return has_text
  end

  def get_clipboard_text
    str = nil
    @clipboard.request_text do |clipboard, text|
      str = text
    end
    return str
  end

  def open_new_window
    win = MainWindow.new
    win.show_all
    $WINDOWS << win
    # フォーカスを動かす？
    return win
  end

  def set_filename(filename)
    @buffer.filename = File.expand_path(filename)
    update_title
  end

  # Open new file, or rather, clear away whatever is in the buffer,
  # and dissociate it with any file
  # XXX これ多分作り直し
  def new_file
    if @buffer.modified?
      rv = ask_continue_without_save
      return if rv == false
    end

    @search_term = nil

    @buffer.text = ""
    @buffer.modified = false
    @undo_stack.clear
    @redo_stack.clear

    update_title
  end

  def apply_font_size
    @font_cache = [] unless @font_cache 
    if not @font_cache[@current_point]
      @font_cache[@current_point] = Pango::FontDescription.new("#{@current_point}")
    end
    desc = @font_cache[@current_point]
    style = @textview.modifier_style
    style.font_desc = desc
    @textview.modify_style(style)
  end

  def create_widgets
    # メニューバー
    @menubar = @uimanager.get_widget("ui/menubar")

    # default settings
    @encoding_label = Label.new(enc2str(ENCODING_UTF8_BOM))
    @encoding_button = Button.new
    @encoding_button.border_width = 0
    @encoding_button.relief = RELIEF_NONE
    @encoding_button.add @encoding_label

    @EOL_button = Button.new
    @EOL_button.border_width = 0
    @EOL_label = Label.new("CR+LF")
    @EOL_button.add @EOL_label
    @EOL_button.relief = RELIEF_NONE

    # TextView
    @buffer = create_new_buffer(SCRATCH_BUFFER_NAME)
    @buffer.major_mode = $ruby_mode
    @buffer.modified = false
    @textview = TextView.new(@buffer)
    @_textview = @textview # backup the original 
    @textview.name = "buffer"
    @textview.set_no_show_all(true)
    @textview.wrap_mode = TextTag::WRAP_CHAR
    #    @textview.border_width = 2
    @textview.left_margin = 3
    @textview.pixels_above_lines = 2

    @scrolled_window = ScrolledWindow.new
    @scrolled_window.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_ALWAYS)
    create_new_buffer("*Messages*")
#    @buffer.create_mark("mark", @buffer.start_iter, true)
#    @buffer.text = ""
    @vbox = VBox.new

    @macify_button = Button.new("Mac式に解釈する")

    @infobar = InfoBar.new
    @infobar.no_show_all = true
    @infobar_label = Label.new("This message is not supposed to show.")
    @infobar_label.xalign = 0
    @infobar_label.wrap = false
    @infobar_label.show
#    @infobar.add_button Gtk::Stock::OK, Gtk::Dialog::RESPONSE_OK
    @infobar.content_area.pack_start(@infobar_label, true)

    @status_bar_hbox = HBox.new(false, 5)
    @charinfo_label = Label.new("n/a")
    @character_label = Label.new("A")
    @character_label.width_request = 32
    @character_label.height_request = 32
    @character_label.name = "character"
    @charinfo_label.name = "charinfo"
    @character_label.no_show_all =true # disabled  by default
    @charinfo_label.no_show_all =true  # disabled  by default
    @position_label = Label.new("n/a")

    @modeline_label = Label.new("")
    @modeline_label.name = "modeline"
    @modeline_label.xalign =0 # 左寄せ
  end

  def layout_widgets
    @vbox.pack_start(@menubar, false)

#    @vbox.pack_start(HSeparator.new, false)
    
    @scrolled_window.add @textview
    @vbox.add @scrolled_window

    @vbox.pack_start(HSeparator.new, false)

    @minibuffer = create_new_buffer("*Minibuffer*")
    @minibuffer_view = TextView.new(@minibuffer)
    @minibuffer_view.no_show_all = true
    @minibuffer_view.name = "minibuffer"
    @minibuffer_view.wrap_mode = TextTag::WRAP_CHAR
    @minibuffer_view.sensitive = false
    @minibuffer_view.set_size_request(-1, 19)
    @buffers.delete(@minibuffer) # バッファー一覧から削除する

    @vbox.pack_end(@minibuffer_view, false)
    @separator_above_minibuffer = HSeparator.new
    @vbox.pack_end(@separator_above_minibuffer, false)

    @status_bar_hbox.pack_start(@modeline_label, false)

    @status_bar_hbox.pack_start(@character_label, false)
    @status_bar_hbox.pack_start(@charinfo_label, false)
    @status_bar_hbox.pack_end(Label.new(""), false) # for spacing
    @status_bar_hbox.pack_end(@EOL_button, false)
    @status_bar_hbox.pack_end(VSeparator.new, false)
    @status_bar_hbox.pack_end(@encoding_button, false)
    @status_bar_hbox.pack_end(VSeparator.new, false)
    @status_bar_hbox.pack_end(@position_label, false)
    @status_bar_hbox.pack_end(VSeparator.new, false)
    @vbox.pack_end(@status_bar_hbox, false)
    self.add @vbox
    self.set_default_size(640, 640)

    openrecent = @uimanager.get_widget("ui/menubar/FileMenu/OpenRecent")
    @recent_chooser_menu = RecentChooserMenu.new
    @recent_chooser_menu.local_only = true
    @recent_chooser_menu.limit = 20
    @recent_chooser_menu.sort_type = RecentChooser::SORT_MRU
    @recent_chooser_menu.signal_connect("item-activated") do |w|
      uri = w.current_uri
      filename, hostname = GLib.filename_from_uri(uri)[0]
      filename.force_encoding("UTF-8")
      if @buffer.modified? and ask_continue_without_save \
        or not @buffer.modified?
        load_file(filename) and Gtk::RecentManager.default.add_item(uri)
      end
    end
    openrecent.submenu = @recent_chooser_menu

    buffers_menu_item = @uimanager.get_widget("ui/menubar/BuffersMenu")
    buffers_menu_item.signal_connect("activate") do
      on_buffers_menu_open
    end
    @buffers_menu = Menu.new
    buffers_menu_item.submenu = @buffers_menu

    @vbox.pack_end(@infobar, false)
  end


  # array には str で始まって
  # str よりも長い文字列が入っている
  def try_complete(str, array)
    i = str.size
    tail = ""
    array = array.dup 
    s1 =  array.shift
    while true
      c = s1[i]
      at_least_one = false
      all = true
      array.each do |s|
        if s[i] != c
          all = false
        else
          at_least_one = true
        end
      end
      if all
        tail += c 
        i += 1
      else
        break
      end
    end
    return tail
  end

  # １頁にファイルをいくつ表示するか
  LINES_PER_PAGE = 10
  # ファイル名の候補を表示する
  # やばい何書いてるかわからないｗｗｗｗ
  # tab_count % pages == page_num?
  def info_list_candidates(head, list, tab_count = 0)
    if head =~ /\//
      if head[-1] != "/"
        head = head.sub(/\/[^\/]+$/, "") + "/"
      end
    else
      head = ""
    end
    pages = list.size / LINES_PER_PAGE
    pages += 1 if list.size % LINES_PER_PAGE > 0 # あまりが出たらもう１頁
    if tab_count >= pages
      tab_count = tab_count % pages
      beep if tab_count == 0
    end
    buf = "#{list.size} candidates. Page #{tab_count+1} of #{pages}\n\n"
    range = list[tab_count*LINES_PER_PAGE...(tab_count+1)*LINES_PER_PAGE]
    range.each_with_index do |path, i|
      buf += path[head.size..-1] + "\n"
    end
    buf += "\n" * (LINES_PER_PAGE - range.size)
    if pages > tab_count+1
      buf += "[...]\n" 
    else
      buf += "[End of List]\n"
    end
    info(buf)
  end

  # scanf みたいにして、変数をブロックに渡したい。
  # replace-regexp みたいに２つ以上の引数も取れた方がいい？
  # %?: ファイル名（補完が効く）
  # %?: メソッド名（補完が効く）
  # takes a block

  def prompt(prompt, default_str = "")
    return unless  minibuffer_lock
    edit_view = @textview
    buffer = @buffer


    @minibuffer_view.grab_focus
    buf = @minibuffer
    buf.insert(buf.start_iter, "#{prompt}", "prompt")
    buf.insert(buf.end_iter, default_str)
      
    tab_count = 0
    h = @minibuffer_view.signal_connect("key-press-event") do |w, e|
      if e.keyval == Gdk::Keyval::GDK_Return
        path = buf.text[(prompt.size)..-1]
        @textview = edit_view
        @buffer = buffer
        edit_view.grab_focus
        @minibuffer_view.signal_handler_disconnect(h)
        clear_minibuffer #@minibuffer.text = ""
        minibuffer_unlock
        yield(path)
        true
      elsif e.keyval == Gdk::Keyval::GDK_g and e.state == Gdk::Window::CONTROL_MASK
        tab_count = 0
        message("Quit")
        Gdk.beep
        clear_minibuffer #buf.text = ""
        minibuffer_unlock
        @minibuffer_view.signal_handler_disconnect(h)
        edit_view.grab_focus
#        @infobar.hide
        true
      else
        false
      end
    end
  end

  # ミニバッファーを使いたい時に呼び出す
  def minibuffer_lock
    if @mb_lock
      message("ミニバッファーを再帰的に使うことはできません\nミニバッファーで C-g を押すと処理を中断できます")
      beep
      return false
    else
      @mb_lock = true
      @minibuffer_view.sensitive = true
      return true
    end
  end

  # ミニバッファーを使い終わったら呼ぶ
  def minibuffer_unlock
    @mb_lock = false
    @minibuffer_view.sensitive = false
    # ここでフォーカス動かさんでいいの？
  end

  # ビープ音を鳴らす
  # というか、Windows のベル音が出る
  def beep
    Gdk.beep
  end

  # find-file で使われるパス記法
  def interpret_path(path)
    if path =~ /.*(\/\/)/ # それ以前を無視してルート
      path = "/" + $'
    elsif path =~ /.*~/   # それ以前を無視してホーム
      rest = $'
      path = @home_dir.gsub(/\\/, "/") + "/" + rest
      path.gsub!(/\/\//, "/")
    end
    return path
  end

  def filename_prompt(prompt)
    return unless minibuffer_lock

    invoker = @textview

    clear_minibuffer
    @minibuffer_view.grab_focus
    buf = @minibuffer
    buf.insert(buf.start_iter, "#{prompt}", "prompt")
    buf.insert(buf.end_iter, @buffer.filename ? File.dirname(@buffer.filename) + "/" : Dir.getwd + "/") 
    
    tab_count = 0
#    h = @minibuffer_view.signal_connect("key-press-event") do
    @minibuffer_key_handler = proc do |w, e|
      if e.keyval == Gdk::Keyval::GDK_Return
        tab_count= 0
        path = buf.text[(prompt.size)..-1]
        path = interpret_path (path)
        @textview = invoker
        @buffer = @textview.buffer
        yield(path)
        invoker.grab_focus
#        @minibuffer_view.signal_handler_disconnect(h)
        @minibuffer_key_handler = nil
#        other_window
        @infobar.hide
        @minibuffer.text = ""
        minibuffer_unlock
        true
      elsif e.keyval == Gdk::Keyval::GDK_Tab
        path = buf.text[(prompt.size)..-1]
        path = interpret_path(path)
        a = Dir.glob("#{path}*")
        if File.exist? path
          if a.size > 1
            if tab_count == 0
              info("[Complete, but not unique]")
            else
              info_list_candidates(path, a, tab_count - 1)
            end
          elsif File.directory? path
            if path[-1] == "/"
              info_list_candidates(path, a, tab_count)
            else
              @minibuffer_view.insert_at_cursor("/")
              tab_count = 0
            end
          else
            info("[Sole completion]")
          end
        else
          case a.size
          when 0
            info("[No match]")
            Gdk.beep
          when 1
            rest = a[0][path.size..-1]
            if File.directory?(path+rest)
              rest += "/"
            end
            @minibuffer_view.insert_at_cursor(rest)
          else
            p path
            tail = try_complete(path, a)
            p tail
            @minibuffer_view.insert_at_cursor(tail)
            info_list_candidates(path, a, tab_count)
          end
        end
        tab_count += 1
        true
      elsif e.keyval == Gdk::Keyval::GDK_g and e.state == Gdk::Window::CONTROL_MASK
        tab_count = 0
        message("Quit")
        Gdk.beep
        buf.text = ""
        @minibuffer_key_handler = nil
#        @minibuffer_view.signal_handler_disconnect(h)
        other_window
        minibuffer_unlock
        #        @infobar.hide
        true
      elsif e.keyval == Gdk::Keyval::GDK_a and e.state == Gdk::Window::CONTROL_MASK
        move_beginning_of_line
        forward_char(prompt.size)
        true
      else
        @infobar.hide
        tab_count = 0
        false
      end
    end
  end

  def eval_expression
    prompt("Eval: ") do |exp|
      str = eval_inspect(exp)
      message(str)
    end
  end

  def execute_command
#    @minibuffer_view
    @minibuffer_view.grab_focus
    prompt("M-x ") do |cmd|
      cmd.gsub!(/-/, "_")
      do_execute_command(cmd.to_sym)
#      str = eval_inspect(cmd)
      # message(str)
    end
    # enter into gets mode
  end

  def create_minibuffer_tags
    @minibuffer.create_tag('prompt', 'foreground'=>"#0000BB", "editable"=>false, 'font'=>'Bold')
    #    @minibuffer.create_tag('prompt', 'foreground'=>"#AAAAFF", "editable"=>false, 'font'=>'Bold')
  end

  # Emacs 系　キーバインドを設定する
  def setup_global_keybind
    # 基本的なカーソル移動
    global_set_key "C-f", :forward_char 
    global_set_key "C-b", :backward_char 
    global_set_key "C-o", :open_line 
    global_set_key "C-n", :next_line 
    global_set_key "C-p", :previous_line 
    global_set_key "C-a", :move_beginning_of_line 
    global_set_key "C-e", :move_end_of_line 

    # 単語移動
    global_set_key "M-f", :forward_word
    global_set_key "M-b", :backward_word

    # ページアップ・ダウン
    global_set_key "C-v", :scroll_up
    global_set_key "M-v", :scroll_down

    global_set_key "M-<", :beginning_of_buffer
    global_set_key "M->", :end_of_buffer

    global_set_key "C-l", :scroll_cursor_onscreen

    global_set_key "M-x", :execute_command 

#    global_set_key "C-j", :eval_print_selection_or_line 
    global_set_key "C-j", proc { insert("\n") }

    global_set_key "C-xC-f", :find_file
    global_set_key "C-xC-e", :eval_selection_or_line
    global_set_key "C-xC-s", :save_buffer
    global_set_key "C-xs", :save_some_buffers
    global_set_key "C-xC-c", :quit
    global_set_key "C-/", :undo
    global_set_key "C-xu", :undo
    global_set_key "M-%", :open_replace_dialog
    # global_set_key "<F1>", :restart
    global_set_key "C-M-<BackSpace>", :restart

    global_set_key "C-<space>", :set_mark
    global_set_key "C-d", :delete_char 
    global_set_key "C-w", :kill_region
    global_set_key "M-w", :copy_region
    global_set_key "C-y", :yank
    global_set_key "C-xC-x", :exchange_point_and_mark

    global_set_key "C-hk", :describe_key
    global_set_key "C-k", :kill_line


    global_set_key "C-xo", :other_window
    global_set_key "C-s", :search_forward
    global_set_key "C-r", :search_backward
    global_set_key "C-xC-t", :delete_all_output
  end

  def add_default_filters(filechooser)
    all = FileFilter.new
    all.add_pattern("*")
    all.name = "すべてのファイル (*.*)"
    txt = FileFilter.new
    txt.add_pattern("*.txt")
    txt.name = "テキストファイル (*.txt)"
    filechooser.add_filter all
    filechooser.add_filter txt
  end

  def open_file
    if @buffer.modified?
      return unless ask_continue_without_save
    end
    dialog = FileChooserDialog.new("Open File",
                                   self,
                                   FileChooser::ACTION_OPEN,
                                   nil,
                                   [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL],
                                   [Gtk::Stock::OPEN, Gtk::Dialog::RESPONSE_ACCEPT])
    add_default_filters(dialog)
    if @buffer.filename
      dialog.current_folder = File.dirname(@buffer.filename)
    end
    c = ComboBox.new
    l = Label.new("文字エンコーディング:")
#    l.xalign =1
    c = create_encoding_combobox
    c.active = 0
    hbox = HBox.new(false, 10)
    hbox.border_width =5
    hbox.pack_end(c, false)
    hbox.pack_end(l, false)

    dialog.vbox.pack_start(hbox, false)
    hbox.show_all
    
    case dialog.run
    when Dialog::RESPONSE_ACCEPT
      load_file(dialog.filename, c.active)
      dialog.destroy
    else
      dialog.destroy
    end
  end

  def connect_signals
    keybuffer = []
    id = @minibuffer_view.signal_connect("key-press-event") do |w, e|
      @textview = w
      @buffer = w.buffer
      @event = e
      rv = key_handler(w, e, keybuffer)
      next rv
    end

    # 同じフォルダのファイル
    @same_dir_menu_item = @uimanager.get_widget("ui/menubar/FileMenu/SameDir")
    sd_menu = Menu.new.show
    @same_dir_menu_item.submenu = sd_menu
    @same_dir_menu_item.signal_connect("activate") do
#      next unless @buffer.filename
      sd_menu.children.each {|i| sd_menu.remove(i) }
      dir = @buffer.filename ? File.dirname(@buffer.filename) : dir = Dir.getwd
      files = Dir.glob(dir + "/*.{txt,rb,c,cpp,h,hpp,c++,h++}")
      i = MenuItem.new(dir, false).show
      i.signal_connect("activate") { spawn("explorer", dos_path(dir)) }
      sd_menu.append(i)
      sep = MenuItem.new.show
      sd_menu.append(sep)
      files.each do |f|
        i = MenuItem.new(File.basename(f), false)
        i.signal_connect("activate") do
          load_file(f)
        end
        i.show
        sd_menu.append(i)
      end
    end
    

    self.signal_connect("destroy") {
      @timeout_tags.each do |n|
        Gtk.timeout_remove(n)
      end
      $WINDOWS.delete(self)
      if $WINDOWS.empty?
        Gtk.main_quit
      end
    }
    signal_connect("delete-event") {
      close
      true # if we return false here, destroy signal would be emitted
    }

    @timeout_tags << Gtk.timeout_add(500) {
      update_status_bar
      true
    }

    # キーでカーソルが動かされたらステータスバーを更新する
    @textview.signal_connect("move-cursor") {
      update_status_bar
    }
    @textview.signal_connect("key-press-event") do |w, e|
      # clear_minibuffer
      @infobar.hide
      false
    end
    @textview.signal_connect("button-press-event") do |w, e|
      #      clear_minibuffer
      @infobar.hide
      false
    end
    # @minibuffer_view.buffer.signal_connect("changed") do |w|
    #   if w.text == ""
    #     @minibuffer_view.hide
    #   else
    #     @minibuffer_view.show
    #   end
    # end

    # @menubar.children.each do |item|
    #   item.signal_connect("activate") do
    #     textview_unfocus
    #   end
    #   item.submenu.signal_connect("selection-done") do
    #     @textview.grab_focus
    #   end
    #   item.submenu.signal_connect("deactivate") do
    #     @textview.grab_focus
    #   end
    # end

    @encoding_popup = @uimanager.get_widget("/EncodingPopup")
    @encoding_button.signal_connect("clicked") {
      @encoding_popup.popup(nil, nil, 1, 0)
    }
    @EOL_popup = @uimanager.get_widget("/EOLPopup")
    @EOL_button.signal_connect("clicked") {
      @EOL_popup.popup(nil, nil, 1, 0)
    }

    # Infobar aka minibuffer?
    @infobar.signal_connect("response") do |d, res|
      case res
      when Gtk::Dialog::RESPONSE_OK
        @infobar.hide
      else
        raise "ここには到達しないと思うの"
      end
    end

    # @textview.signal_connect("preedit-changed") do |w, preedit|
    #   info("※ IME が入っています")
    # end
  end

  def end_of_buffer
    @buffer.place_cursor( @buffer.end_iter )
    scroll_cursor_onscreen
  end

  def beginning_of_buffer
    @buffer.place_cursor( @buffer.start_iter )
    scroll_cursor_onscreen
  end

  def find_file
    edit_view = @textview
    buffer = @textview.buffer

    # 編集バッファから C-x C-f により実行される
    filename_prompt("Find file: ") do |path|
      if true # File.exist? path
        @textview = edit_view # こんなことしたくない
        @buffer = buffer
        if File.directory?(path)
          directory_list(path)
        else
          load_file(path)
        end
        self.grab_focus
        edit_view.grab_focus
      else
        win = open_new_window
        win.set_filename(path)
      end
      clear_minibuffer
    end
  end

  def print_keymap
    @global_keymap.each do |entry|
      strokes, cmd = entry

      key = strokes.map{|s| key2str(*s)}.join(" ")
      insert "#{key}\t#{cmd.to_s}\n"
    end
  end

  def get_buffer(name)
    @buffers.each do |buf|
      if name == buf.buffer_name
        return buf
      end
    end
    return nil
  end

  def message(fmt, *args)
    str = sprintf(fmt, *args)

    @infobar_label.text = str
    @infobar.show

    @timeout_tags << Gtk.timeout_add(1000) {
      if @infobar_label.text == str
        @infobar.hide
      end
      false
    }

    buf = get_buffer("*Messages*") || create_new_buffer("*Messages*")
    
    buf.place_cursor(buf.end_iter)
    buf.insert_at_cursor(str + "\n")

    # scroll_cursor_onscreen
  end

   def clear_minibuffer
     @minibuffer_view.buffer.text = ""
 #    @minibuffer_view.hide
   end

  # InfoBar
  def info(str)
    @infobar_label.text = str
    @infobar.show
  end

  def info_markup(str)
    @infobar_label.markup = str
    @infobar.show
  end

  def update_status_bar
    pos = @buffer.cursor_position
    iter = @buffer.get_iter_at_offset(pos)
    c = iter.char
#    next true if pos == @last_position and c == @last_char
    @last_position = pos
    @last_char = c
    if c == ""
      charinfo = "[ファイルの終端です]"
      char = ""
    else
      codepoint = sprintf("%04X", c.ord)
      name = $UNICODE_DATA[codepoint]
      char = c.inspect[1...-1] # cut off quote marks
      char = CGI::escapeHTML(char)
      #        name = CGI::escapeHTML(name)
      charinfo = "  U+#{codepoint}  #{name}"
    end
    @character_label.text = char
    @charinfo_label.text = "#{charinfo}"
    @position_label.text = sprintf("%4d行、%3d列", iter.line+1, iter.line_offset+1)


    @encoding_label.text = enc2str(@buffer.encoding)
    @EOL_label.text = eol2str(@buffer.eol)
  end


  def error_message(msg)
    dialog = MessageDialog.new(self, Dialog::DESTROY_WITH_PARENT,
                               MessageDialog::ERROR,
                               Gtk::MessageDialog::BUTTONS_OK,
                               msg)
    dialog.title = $APPLICATION_NAME
    Gdk.beep
    dialog.run { dialog.destroy }
  end

  # str に適切な改行文字を決定する
  def guess_eol(str)
    enc = str.encoding
    str.force_encoding("ASCII-8BIT")
    begin
      if str =~ /\r\n/
        return "\r\n" 
      elsif str =~ /\n/
        return "\n" 
      elsif str =~ /\r/
          return "\r"
      end

      # 改行文字がない場合、エンコーディングから
      # 設定する。
      case @textview.buffer.encoding
      when ENCODING_MACJAPANESE
        return "\r"
      when ENCODING_EUC_JP
        return "\n"
      else
        # デフォルト
        return "\r\n"
      end
    ensure
      str.force_encoding(enc)
    end
  end

  # 文字エンコーディングを判別する
  def auto_detect(str)
    valid_p = GLib.utf8_validate(str)
    if valid_p
      str.force_encoding("utf-8")
      if str[0] == "\uFEFF" #BOM
        return ENCODING_UTF8_BOM
      else
        return ENCODING_UTF8_NOBOM
      end
    else
      guess = NKF.guess(str).to_s
      case guess
      when "Shift_JIS", "Windows-31J"
        if guess_eol(str) == "\r"
          return ENCODING_MACJAPANESE
        else
          return ENCODING_CP932
        end
      when "EUC-JP"
        return ENCODING_EUC_JP
      else
        raise "auto detect failed"
      end
    end
  end

  # 新しいバッファーを作る
  def create_new_buffer(buffer_name)
    if get_buffer(buffer_name) != nil
      raise "そのバッファーは既にあります"
    end

    buffer = Buffer.new
    buffer.buffer_name = buffer_name
    buffer.undo_stack = []
    buffer.redo_stack = []

    temp_stack = []  # ユーザーアクションの間、操作を保存する

    # シグナルハンドラーの接続

    # 変更が起こったらステータスバーを更新する
    buffer.signal_connect("changed") { update_status_bar }
    buffer.signal_connect("modified-changed") { update_title }

    # アンドゥー機能のために
    buffer.signal_connect("begin-user-action") do
      temp_stack = []
    end
    buffer.signal_connect("end-user-action") do
      buffer.undo_stack << temp_stack unless temp_stack.empty?
    end

    # バッファー変更操作を記録
    id1 = buffer.signal_connect("insert-text") do |widget, iter, text, bytes|
      now = Time.now
      lastcmds = nil
      if not temp_stack.empty?
        lastcmds = temp_stack 
      else
        lastcmds = buffer.undo_stack.last # might be nil
      end
      if lastcmds and lastcmds.last["action"] == "insert" and now - lastcmds.last["time"] < 1.0 \
        and iter.offset == lastcmds.last["offset"] + lastcmds.last["text"].size \
        and lastcmds.last["text"][-1] !~ /\s/ # スペースの連続がアンドゥーできなくなる
        lastcmds.last["text"] += text
      else
        temp_stack.push({"action"=>"insert", "offset"=>iter.offset, "text"=>text, "cursor_offset"=>buffer.cursor_position, "time"=>now})
      end
      buffer.redo_stack.clear
    end
    id2 = buffer.signal_connect("delete-range") do |widget, iter1, iter2|
      now = Time.now
      deleted = buffer.get_slice(iter1, iter2)
      temp_stack.push({"action"=>"delete", "offset"=>iter1.offset, "text"=>deleted, "cursor_offset"=>buffer.cursor_position, "time"=>now})
      buffer.redo_stack.clear
    end

    buffer.insert_recorder_id = id1
    buffer.delete_recorder_id = id2

    # Emacs のマークに対応する
    buffer.create_mark("mark", buffer.start_iter, true)

#    buffer.create_tags

    @buffers << buffer
    return buffer
  end

  def kill_buffer(buffer = nil)
    unless buffer
      prompt("Kill buffer (default #{@buffer.buffer_name}): ") do |name|
        if name == ""
          kill_buffer(@buffer)
        else
          b = get_buffer(name)
          if b
            kill_buffer(b) 
          else
            beep
            message("そんなバッファーないよ")
          end
        end
      end
      return
    end
    if @buffer.filename and @buffer.modified?
      ask_continue_without_save or return
    end

    @buffers.delete(@buffer)
    switch_to_any_buffer
  end

  def switch_to_any_buffer
    buffer = nil
    if @previous and @buffers.include? @previous
      buffer = @previous 
    elsif @buffers[0]
      buffer = @buffers[0]
    end
    # バッファーがひとつもない
    unless buffer
      buffer = create_new_buffer(SCRATCH_BUFFER_NAME) 
      buffer.major_mode = $ruby_mode
    end
    @buffer = @textview.buffer = buffer
    scroll_cursor_onscreen
    update_title; update_status_bar
  end

  def switch_to_buffer(buffer = nil)
    if buffer == nil
      if @previous and @buffers.include? @previous
        prompt("Switch to buffer (default #{@previous.buffer_name}): ") do |name|
          if name == ""
            switch_to_buffer(@previous)
          else
            b = get_buffer(name)
            b = create_new_buffer(name) unless b
            switch_to_buffer(b)
          end
        end
      end
      return
    end
    unless @buffers.include? buffer
      beep
      message("that buffer does not exist any more")
      return
    end
    @previous = @buffer
    @textview.buffer = buffer
    @buffer = buffer
    scroll_cursor_onscreen
    update_title
    update_status_bar
  end

  # Emacs モードなら、新しいバッファーに、メモ帳モードなら現在のバッファーに
  # ファイルを読み込む
  def load_file(filename, encoding = ENCODING_AUTO_DETECT)
    # 既に開いているならそちらのバッファーに切り替える
    @buffers.each do |b|
      if b.filename and File.identical?(b.filename, filename)
        switch_to_buffer(b)
        return 
      end
    end

    # 文字コード問題などで読み込みに失敗した場合に戻れるようにする
    @previous = @buffer

    buffer_name = File.basename(filename)
    buffer = create_new_buffer(buffer_name)
    # 自動モード選択
    @auto_mode_list.each do |re, mode|
      if buffer_name =~ re
        buffer.major_mode = mode
      end
    end
    @textview.buffer = buffer
    @buffer = buffer

    if File.exist? filename
      unless do_load_file(filename, encoding)
        @buffers.delete(@buffer)
        @textview.buffer = @buffer = @previous
      end
    else
      @buffer.filename = filename
      @buffer.modified = true
    end
    update_title
    update_status_bar
  end

  def do_load_file(filename, encoding = ENCODING_AUTO_DETECT)
    filename = File.expand_path(filename) # i don't know why this returns (purportedly)SJIS string
    filename.force_encoding("UTF-8")
    begin
      f = File.new(filename, "rb")

      str = f.read

      case encoding
      when ENCODING_AUTO_DETECT
        f.close
        return do_load_file(filename, auto_detect(str))
      when ENCODING_CP932
        str.force_encoding("CP932")
        str = str.encode("UTF-8")
        set_encoding(encoding)
      when ENCODING_MACJAPANESE
        str.force_encoding("MacJapanese")
        str = MacJapanese.to_utf8(str)
        set_encoding(encoding)
      when ENCODING_UTF8_NOBOM
        if not GLib.utf8_validate(str)
          raise Encoding::InvalidByteSequenceError
        end
        set_encoding(encoding)
      when ENCODING_UTF8_BOM
#        p str.force_encoding("UTF-8")
        if not GLib.utf8_validate(str) or str.force_encoding("UTF-8")[0] != "\uFEFF"
          raise Encoding::InvalidByteSequenceError
        end
        set_encoding(encoding)
      when ENCODING_EUC_JP
        str.force_encoding("EUC-JP")
        str = str.encode("UTF-8")
        set_encoding(encoding)
      else
        raise "should not reach here"
      end
      str.force_encoding("UTF-8")

      if @buffer.encoding == ENCODING_UTF8_BOM
        str = str[1..-1] # cut off BOM
      end

      eol = guess_eol(str)
      set_eol(eol)

      str.gsub!(/#{eol}/, "\n")
    rescue Encoding::InvalidByteSequenceError=>error
      error_message("指定されたエンコーディング(#{enc2str(encoding)})では開けません。")
      return false
    rescue =>error
      dialog = MessageDialog.new(self, Dialog::DESTROY_WITH_PARENT,
                                 MessageDialog::ERROR,
                                 Gtk::MessageDialog::BUTTONS_OK,
                                 sprintf("%s: %s\n%s\n", error.class,
                                         error.message,
                                         error.backtrace.join("\n")))
      dialog.title = "エラー"
      dialog.run { dialog.destroy }
      return false
    end

    @encoding_label.text = enc2str(@buffer.encoding)

    @buffer.signal_handler_block(@buffer.insert_recorder_id)
    @buffer.signal_handler_block(@buffer.delete_recorder_id)
    @buffer.text = ""
    @buffer.insert(@buffer.start_iter, str)
    @buffer.signal_handler_unblock(@buffer.insert_recorder_id)
    @buffer.signal_handler_unblock(@buffer.delete_recorder_id)

    @buffer.undo_stack.clear
    @buffer.redo_stack.clear

    @buffer.filename = filename
    update_title
    # 文書の最初に移動する
    @buffer.place_cursor(@buffer.start_iter)
    @textview.grab_focus
#    error_message(@textview.buffer.buffer_name)
    scroll_cursor_onscreen
    
    @buffer.modified = false

    prok =  @buffer.major_mode.on_load
    prok.call if prok 

    return true
  end

  def dos_filename(filename)
    filename = filename.gsub(/\//, "\\")
    # upcase the drive letter
    filename[0] = $1.upcase if filename =~ /^([a-z]):/
    return filename
  end
  alias dos_path dos_filename

  def update_title
    filename = nil
    if @buffer.filename
      filename = dos_filename(@buffer.filename)
    end
    self.title = sprintf("%s - %s %s%s- %s",
                         @buffer.buffer_name,
                         filename,
                         @buffer.modified? ? "(更新) " : "",
                         @textview.editable? ? "" : "(閲覧モード) ",
                         $APPLICATION_NAME)

    # タイトルじゃないけど
    st = nil
    if @buffer.read_only? and not @buffer.modified?
      st = "%%"
    elsif @buffer.read_only? and @buffer.modified?
      st = "%*" #これでいいんだっけ？？
    elsif not @buffer.read_only? and not @buffer.modified?
      st = "--"
    elsif not @buffer.read_only? and @buffer.modified?
      st = "**"
    else
      raise "バグだわー"
    end
    @modeline_label.text =
      sprintf(" %s  %-20s (%s)",
              st,
              @buffer.buffer_name,
              [@buffer.major_mode.name, *@buffer.minor_modes.map{|m|m.name}].join(" "))
                              
  end

  # １単語進む。日本語のあつかいがおかしい。
  def forward_word(n = 1)
    @textview.signal_emit("move-cursor", MOVEMENT_WORDS, n, false)
  end

  # １単語戻る。バッファの先頭に移動できない問題があったはず
  def backward_word(n = 1)
    @textview.signal_emit("move-cursor", MOVEMENT_WORDS, -n, false)
  end

  def modified?
    @buffer.modified?
  end
  
  def save_some_buffers
    saved = 0
    @buffers.each do |b|
      if b.modified? and b.filename
        @textview.buffer = @buffer = b
        save_file
        saved += 1
      end
    end
    if saved == 0
      message("(保存の必要はありませんでした)")
    else
      message("#{saved} 個のファイルを保存しました")
    end
  end

  def save_buffer
    if @buffer.modified?
      save_file
    else
      message("(変更されていません)")
    end
  end
      

  # return true if saved, false otherwise
  def save_file
    if @buffer.filename == nil
      return save_as
#    elsif not @buffer.modified?
#     Gdk.beep
#      return false
    end
    begin
      do_save_file
    rescue =>error
      dialog = MessageDialog.new(self, Dialog::DESTROY_WITH_PARENT,
                                 MessageDialog::ERROR,
                                 Gtk::MessageDialog::BUTTONS_OK,
                                 sprintf("%s: %s\n%s\n", error.class,
                                         error.message,
                                         error.backtrace.join("\n")))
      dialog.title = "エラー"
      dialog.run { dialog.destroy }
      return false
    end
    return true
  end

  def do_save_file
    buf = @buffer.text
    case @buffer.encoding
    when ENCODING_UTF8_NOBOM
    when ENCODING_UTF8_BOM
      buf = "\uFEFF" + buf
    when ENCODING_CP932
      buf = buf.encode("CP932")
    when ENCODING_MACJAPANESE
      buf = MacJapanese.to_mac_japanese(buf)
    when ENCODING_EUC_JP
      buf = buf.encode("EUC-JP")
    end

    buf.gsub!(/\n/, @buffer.eol)

    f = File.open(@buffer.filename, "wb")
    f.write(buf)
    f.close

    @buffer.modified = false
    update_title
    message("保存しました：#{@buffer.filename}")
  end

  def save_as
    dialog = FileChooserDialog.new("Save File",
                                   self,
                                   FileChooser::ACTION_SAVE,
                                   nil,
                                   [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL],
                                   [Gtk::Stock::SAVE, Gtk::Dialog::RESPONSE_ACCEPT])
    add_default_filters(dialog)
    if @buffer.filename
      dialog.current_folder = File.dirname(@buffer.filename)
    end
    loop do 
      case dialog.run
      when Dialog::RESPONSE_ACCEPT
        @buffer.filename = dialog.filename
        update_title
        save_file
        break
      when Dialog::RESPONSE_CANCEL
        break
      else
        break
      end
    end
    dialog.destroy
  end

  # すべての Entry と TextView はここで
  # show しなければならない
  def show_late_widgets
    @textview.show
    @minibuffer_view.show
  end

  SAVE = 1; DISCARD = 2; CANCEL = 3

  # 本当に変更されたバッファーの内容を保存しないのか、訊く。
  # ユーザーが処理の続行を希望する場合は true、キャンセルする場合は false を返す
  def ask_continue_without_save
    name = @buffer.filename ? File.basename(@buffer.filename) : "無題"
    dialog = MessageDialog.new(self, Dialog::DESTROY_WITH_PARENT, MessageDialog::QUESTION, MessageDialog::BUTTONS_NONE, "#{name} への変更内容を保存しますか？")
    dialog.title = $APPLICATION_NAME
    dialog.add_buttons(["保存する", SAVE],
                       ["保存しない", DISCARD],
                       ["キャンセル", CANCEL])
    begin
      dialog.run do |res|
        case res
        when SAVE
          saved_p = save_file
          unless saved_p
            # user cancelled save dialog
            return false
          end
          return true
        when DISCARD
          return true
        when CANCEL
          return false
        else # ダイアログが閉じられた（など？）
          return false
        end
      end
    ensure
      dialog.destroy
    end
  end

  # 保存あるいは破棄でtrue
  def close
    # セーブ判定とか　
    if @buffer.modified?
      unless ask_continue_without_save
        return false
      end
    end
                        
    self.destroy # send "destroy" signal to self
    return true # ここに到達するの？
  end

  # 開かれているすべてのウィンドウを閉じる
  # destroy のシグナルハンドラーがアプリケーションを終了する
  def quit
    $WINDOWS.each do |w|
      if w != self
        w.close or return
      end
    end
    self.close or return
  end

  def drop_files(uri_list)
    uri = uri_list.split(/\r\n/)[0]
    filename = GLib.filename_from_uri(uri)[0]
    filename.force_encoding("UTF-8")
#    error_message(filename.inspect)
    load_file(filename)
  end

  # Widget#show_all をオーバーライド
  # TextView や Entry は show_all で show すると
  # １度他のウィンドウをフォーカスするまで
  # フォーカスを受け取れなくなる
  def show_all
    super
    show_late_widgets
  end
end

# Gdk::Event.handler_set { |event|
#   if event.is_a? Gdk::EventDND
# #    p event.event_type
#     c = event.context
# #    p c.protocol
# #    p c.selection.name
#     if c.protocol == Gdk::DragContext::PROTO_WIN32_DROPFILES
#       Gdk::Selection.convert($window.window, c.selection, Gdk::Atom.intern("uri-list"), event.time)
#       data, prop_type, prop_format = Gdk::Selection.property_get($window.window)
#       p data
#       $window.drop_files(data)
#       c.drop_reply(true, event.time)# Gdk::Event::CURRENT_TIME)
#       c.drop_finish(true, event.time)
#     else
# #      Gtk.main_do_event(event)
#     end
#   else
#     Gtk.main_do_event(event)
#   end
# }

win = MainWindow.new
win.window_position = Window::POS_CENTER
unless ARGV.empty?
  win.load_file(ARGV[0])
  ARGV.clear
end
win.show_all
$WINDOWS << win

Gtk.main

if $RESTART_FLAG
  cmdline = "\"#{get_exec_filename}\" \"#{$PROGRAM_NAME}\""
  cmdline += " \"#{$RESTART_FILENAME}\"" if $RESTART_FILENAME
  spawn(cmdline)
end

exit 0
