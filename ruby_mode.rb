# -*- coding: utf-8 -*-

# コメントテスト
class String
end

module RubyMode
  REG_COMMENT = /#.*$/
  REG_KEYWORD = /\b(class|alias|and|or|break|next|redo|retry|elsif|in|module|return|end|def|do|if|else|elsif|when|case|raise|rescue|ensure|begin|then|proc|until|unless|loop|super|while|for)\b/
  REG_LITERAL = /(\/\/|\/.*?[^\\]\/|".*?[^\\]"|""|'.*?[^\\]'|''|`.*?[^\\]`|``)/
  REG_VAR     = /((\$|@|@@)\w+|true|false|self|nil)/
  REG_CONST   = /\b([A-Z]\w+)\b/
  REG_HERE    = /<<-?[`'"]?(\w+)[`'"]?$.*?^\s*\1$/m
  REG_EMBED   = /^=begin$.*?^=end$/m
  REG_SYMBOL  = /:[a-z_0-9]+/

  def ruby_mode
    mode = @major_mode_list["ruby_mode"]
    unless mode
      @major_mode_list["ruby_mode"] = mode = create_ruby_mode
    end
    @buffer.major_mode = mode
  end

  def goto_definition
    prompt("Method name: ") do |str|
      @search_term = "def #{str}"
      find_next
    end
  end
  
  # Ruby用の Tab に割り当てられることを想定されたインデント関数
  def ruby_indent
    pt = @buffer.get_iter_at_mark( @buffer.get_mark("insert") )
    offset = pt.line_offset
    return if pt.line == 0
    i = 1
    while (above = get_line(pt.line-i)) == ""
      i += 1
      if pt.line - i < 0
        break
      end
    end
    
    cur = get_line(pt.line)
    if above =~ /^\s*/
      above_space = $&
      cur2 = cur.sub(/^\s*/, "")
      move_beginning_of_line
      pt = @buffer.get_iter_at_mark( @buffer.get_mark("insert") )
      if above =~ /^\s*(module|if|def|while|for|ensure|rescue|begin|class|unless|case|when|else|elsif|unless)\b/ or
          above =~ /(\||\bdo)\s*$/
        above_space += "  "
      end
      if cur2 =~ /^\s*((end|when|ensure|rescue|else|elsif)\b|})/
        above_space = above_space[0...-2]
      end
      newline =  above_space + cur2
      unless newline == cur
        kill_line unless pt.ends_line?
        insert(newline) 
      end
      move_beginning_of_line
      newoffset = newline.size - (cur.size - offset)
      newoffset = above_space.size if newoffset < above_space.size
      forward_char(newoffset)
    end
  end

  # Ruby のメソッド定義を検索する
  def goto_definition
    prompt("Method name: ") do |str|
      @search_term = "def #{str}"
      find_next
    end
  end

  # Ruby モードを表す Mode クラスのオブジェクトを作って返す
  def create_ruby_mode
    mode = Mode.new("Ruby モード")
    mode.keymap.define_key("C-0", :goto_definition)
    mode.keymap.define_key("<Tab>", :ruby_indent)
    return mode
  end

  def emphasize_keywords_line
    # ヒアドキュメント内や埋め込みドキュメント内を編集しているのか
    # その行の先頭付近の # や " を削除したのか判定したい。
    # 一つ下の行のタグを見ればわかるかな。
    
    # １つ上の行も見たほうがいい。
    line = get_line_under_cursor
    if line == "=begin" or line == "=end"
      emphasize_keywords # 全バッファを再計算
      return
    end
    
    iter = @buffer.get_iter_at_cursor
    text = get_line_under_cursor
    beg = iter.dup 
    beg.line = iter.line             # 行頭に移動させる
    _end = beg.dup
    _end.forward_chars(text.size)
    lbo = beg.offset  # line beginning offset

    # beg が行頭で _end が行末 Iter

    ["keyword", "literal", "comment", "green", "gold", "skyblue"].each do |tag|
      @buffer.remove_tag(tag, beg, _end)
    end

    # [処理前に削除するタグ, タグ名, 正規表現, [避けるタグ, ...]]
    [
     # コメントっぽいところ
     [nil, "comment", REG_COMMENT, []],
     # 文字リテラルっぽいところをタグる
     [nil, "literal", REG_LITERAL, ["comment"]],
     # 文字リテラルっぽいところの # は無視して
     # コメントをタグり直す
     ["comment", "comment", REG_COMMENT, ["literal"]],
     # もう一度、コメントを避けて文字リテラルをタグる
     ["literal", "literal", REG_LITERAL, ["comment"]],
     # 文字リテラルとコメントを避けてキーワードをタグる
     [nil, "keyword", REG_KEYWORD, ["comment", "literal"]],
     # グローバル・インスタンス変数
     [nil, "gold", REG_VAR, ["comment", "literal"]],
     # 定数
     [nil, "green", REG_CONST, ["comment", "literal", "gold"]],
     # シンボル
     [nil, "skyblue", REG_SYMBOL, ["comment", "literal"]]
    ].each do |del, tag, regexp, tags_to_avoid|
      @buffer.remove_tag(del, beg, _end) if del
      text.scan(regexp) do
        p1, p2 = $~.offset(0)
        i = @buffer.get_iter_at_offset(lbo + p1)
        j = @buffer.get_iter_at_offset(lbo + p2)
        avoid_p = false
        tags_to_avoid.each do |t|
          if i.tags.include? @buffer.tag_table.lookup(t)
            avoid_p = true
            break
          end
        end
        @buffer.apply_tag(tag, i, j) unless avoid_p
      end
    end
    return
  end


  # /hoge/
  def emphasize_keywords
    ["keyword", "literal", "comment", "green", "gold", "skyblue"].each do |tag|
      @buffer.remove_tag(tag, @buffer.start_iter, @buffer.end_iter)
    end
    # [処理前に削除するタグ, タグ名, 正規表現, [避けるタグ, ...]]
    [
     # 埋め込みドキュメント
     [nil, "comment", REG_EMBED, []],
     # リテラルっぽいところ
     [nil, "literal", REG_LITERAL, ["comment"]],
     # コメントっぽいところ
     [nil, "comment", REG_COMMENT, ["literal"]],
     # 文字リテラルっぽいところの # は無視して
     # コメントをタグり直す
     ["literal", "literal", REG_LITERAL, ["comment"]],
     # 文字リテラルとコメントを避けてキーワードをタグる
     [nil, "keyword", REG_KEYWORD, ["comment", "literal"]],
     # ヒアドキュメント（ここでいいのか？？？）
     [nil, "literal", REG_HERE, ["comment"]],
     # グローバル・インスタンス変数
     [nil, "gold", REG_VAR, ["comment", "literal"]],
     # 定数
     [nil, "green", REG_CONST, ["comment", "literal", "gold"]],
     # シンボル
     [nil, "skyblue", REG_SYMBOL, ["comment", "literal"]]
    ].each do |del, tag, regexp, tags_to_avoid|
      @buffer.remove_tag(del, @buffer.start_iter, @buffer.end_iter) if del
      @buffer.text.scan(regexp) do
        p1, p2 = $~.offset(0)
        i = @buffer.get_iter_at_offset(p1)
        j = @buffer.get_iter_at_offset(p2)
        avoid_p = false
        tags_to_avoid.each do |t|
          if i.tags.include? @buffer.tag_table.lookup(t)
            avoid_p = true
            break
          end
        end
        @buffer.apply_tag(tag, i, j) unless avoid_p
      end
    end

    return
  end

  def ruby_indent_region
    i = @buffer.get_iter_at_mark (@buffer.get_mark("mark"))
    j = @buffer.get_iter_at_cursor
    l1 = nil; l2 = nil
    i < j
    if i < j
      l1 = i.line
      l2 = j.line 
    else
      l1 = j.line
      l2 = i.line
    end
    message("#{l1}..#{l2}")
    (l1..l2).each do |n|
      i = @buffer.get_iter_at_cursor
      i.line = n
      @buffer.place_cursor(i)
      ruby_indent
    end
  end

  REG_CLASS = '[A-Z]\w*(::[A-Z]\w*)*'
  # do は別に見る
  REG_BLOCK_KEYWORDS = '\b(unless|class|for|module|def|if|case|begin|until|while)\b'
  def create_index
    debug = false
    
    buf = prepare_output_buffer("*ruby index*",
                                @major_mode_list['grep_mode'])

    message("リストを作っています...") # 表示されないね

    text = @buffer.text
    buffer_name = @buffer.buffer_name

    switch_to_buffer(buf)

    nest_level = 0
    outer_block = nil
    iter = buf.start_iter
    comment = []
    text.split(/\n/).each_with_index do |_line, i|
      # for i in (0...@buffer.line_count)
      # _line = get_line(i)
      line = _line.sub(/(?!#\{)#.*$/, "") # コメントを削除
      if line != _line
        comment << _line
      end
      buf.insert(iter, "DEBUG: #{comment.inspect}\n", "comment")  if debug

      buf.insert(iter, "Line:#{i} Level:#{nest_level} #{_line.inspect}\n", 'literal') if debug
      if line =~ /\s*class\s+(#{REG_CLASS})/
        buf.insert(iter, "#{buffer_name}:#{i+1}", "skyblue")
        buf.insert(iter, ": ")
        buf.insert(iter, "class ")
        buf.insert(iter, $1)
        buf.insert(iter, " " + comment[0], "comment") unless comment.empty?
        buf.insert(iter, "\n")
        outer_block = $1
        nest_level += 1
      elsif line =~ /\s*def\s+([\w\.]+)/
        buf.insert(iter, "#{buffer_name}:#{i+1}", "skyblue")
        buf.insert(iter, ": ")
        name = $1
        buf.insert(iter, "*" * nest_level) if debug
        buf.insert(iter, "")
        if name =~ /[A-Z]\w*\.\w+/
        elsif outer_block
          buf.insert(iter, outer_block)
          name = "#" + name
        end
        buf.insert(iter, name)
        buf.insert(iter, " " + comment[0], "comment") unless comment.empty?
        buf.insert(iter, "\n")
        nest_level += 1
      elsif line =~ /\s*module\s+(\w+)/
        buf.insert(iter, "#{buffer_name}:#{i+1}", "skyblue")
        buf.insert(iter, ": ")
        buf.insert(iter, "module " + $1)
        buf.insert(iter, " " + comment[0], "comment") unless comment.empty?
        buf.insert(iter, "\n")
        outer_block = $1
        nest_level += 1
      elsif line =~ /^\s*#{REG_BLOCK_KEYWORDS}/
        nest_level += 1
      elsif line =~ /\bdo\s*(\|.*\|\s*)?$/
        nest_level += 1
      elsif _line == "" or _line == line
        comment.clear
      end

      # 開いたその行で閉じられた場合も含む
      # "if a then hoge end"
      if line =~ /\bend\s*$/ and line !~ /^=end$/
        buf.insert(iter, "DEBUG: nest_level -= 1\n") if debug
        nest_level -= 1
        if nest_level < 0
          buf.insert(iter, "BUG: negative nest level. reset to 0\n", "comment")
          nest_level = 0
        end
        if nest_level == 0
          outer_block = nil
        end
      end
    end

    iter.line = 0
    buf.place_cursor(iter)
    scroll_cursor_onscreen

    @infobar.hide
  end
end
