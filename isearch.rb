# -*- coding: utf-8 -*-
module ISearchMode

  def create_isearch_mode
    mode = Mode.new("isearch")

    # isearch 時に C-f とか押すと、サーチを終了して
    # 通常のバッファへのコマンドとして認識させるのが
    # 難しい
    mode.keymap.define_key("C-s", :isearch_forward)
#    mode.keymap.define_key("C-r", nil)
    mode.keymap.define_key("C-g", :quit_isearch)
    mode.keymap.define_key("<Return>", :end_isearch)
    mode.keymap.define_key("<BackSpace>", :isearch_delete_backward_char)

    mode.keymap.define_key("<space>", :isearch_self_insert_command)
    mode.keymap.default_proc = proc { isearch_other_command }
    for i in 0x21..0x7e
      name = ascii2name(i.chr)
      if name
        name = "<#{name}>"
      else
        name = i.chr
      end
      mode.keymap.define_key(name, :isearch_self_insert_command)
      puts "mode.keymap.define_key(#{name.inspect}, :isearch_self_insert_command)"
    end
    
    return mode
  end

  def isearch_other_command
    end_isearch
    # これ動かねえだろｗｗｗｗ
    #    return key_handler(@textview, @event, [])
    return false
  end

  def isearch_self_insert_command
    @minibuffer.insert_at_cursor(@event.keyval.chr)
    isearch_forward_next(@search_origin_iter)
  end
  
  def isearch_delete_backward_char
    @minibuffer_view.backspace
    if get_input == ""
      @buffer.place_cursor(@search_origin_iter)
      scroll_cursor_onscreen
      remove_highlight(@buffer)
    else
      isearch_forward_next(@search_origin_iter)
    end
  end

  def beginning_of_input
    @buffer.text =~ /^.+: /
    pos = $&.size
    iter = @buffer.get_iter_at_offset(pos)
    @buffer.place_cursor(iter)
  end
  
  def get_input
    text = @minibuffer.text 
    input = text.sub(/^.+: /, "")
  end

  def isearch_forward_next(origin)
    start_iter, end_iter = origin.forward_search(get_input, TextIter::SEARCH_TEXT_ONLY, nil)
    if start_iter
      origin.buffer.place_cursor(end_iter)
      @textview = @_textview
      @buffer = @textview.buffer
      scroll_cursor_onscreen
      remove_highlight(origin.buffer)
      origin.buffer.apply_tag("highlight", start_iter, end_iter)
    else
      beep
    end
  end

  def isearch_forward
    if @search_origin_iter
      if get_input == ""
        if @previous_search
          @minibuffer.insert_at_cursor(@previous_search)
        else
          beep
          return
        end
      end
      isearch_forward_next(@search_origin_iter.buffer.get_iter_at_cursor)
      return
    else
      @search_origin_iter = @buffer.get_iter_at_cursor
    end
    @search_forward_p = true
    # ロックを無視する
    unless @mb_lock
      minibuffer_lock
    end
    @minibuffer.insert(@minibuffer.start_iter, "Isearch: ", "prompt")
#    @minibuffer_view.grab_focus
    @buffer.minor_modes << @major_mode_list['isearch']
    update_title
  end

  def isearch_backward
    @search_forward_p = false
  end

  def remove_highlight(buf)
    buf.remove_tag("highlight", buf.start_iter, buf.end_iter)
  end

  def quit_isearch
    beep
    remove_highlight( @search_origin_iter.buffer)
    @search_origin_iter.buffer.place_cursor(@search_origin_iter)
#    @minibuffer.mode = $fundamental_mode
    @search_origin_iter.buffer.minor_modes.delete(@major_mode_list['isearch'])
    @search_origin_iter = nil
    clear_minibuffer
    minibuffer_unlock
    @_textview.grab_focus
    @textview = @_textview
    @buffer = @textview.buffer
    scroll_cursor_onscreen
    update_title
  end

  def end_isearch
    @previous_search = get_input
    remove_highlight( @search_origin_iter.buffer)
    @search_origin_iter.buffer.move_mark("mark", @search_origin_iter)
   @search_origin_iter.buffer.minor_modes.delete(@major_mode_list['isearch'])
    @textview.buffer.move_mark("mark", @search_origin_iter)
    message("検索を開始した位置をマークしました")
    @search_origin_iter = nil
#    @minibuffer.mode = $fundamental_mode
    clear_minibuffer
    minibuffer_unlock
    @_textview.grab_focus
    update_title
  end

end
