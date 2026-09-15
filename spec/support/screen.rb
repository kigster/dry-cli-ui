# frozen_string_literal: true

# Plays escape sequences the way a terminal would, far enough to show what a
# person would see once a widget has finished writing. It grows downward
# instead of scrolling, and treats every character as one column wide.
class Screen
  CSI = /\A\e\[([\d;?]*)([A-Za-z])/

  # @param text [String] everything written to the terminal
  def initialize(text)
    @rows = [[]]
    @row = 0
    @col = 0
    @saved = [0, 0]
    play(text)
  end

  # @return [Array<String>] each row, right-trimmed, trailing blank rows dropped
  def lines
    @rows.map { |row| row.map { |char| char || " " }.join.rstrip }.reverse.drop_while(&:empty?).reverse
  end

  # @return [Array(Integer, Integer)] where the cursor ended
  def cursor = [@row, @col]

  private

  def play(text)
    until text.empty?
      if (match = text.match(CSI))
        control(match[1], match[2])
        text = match.post_match
      elsif text.start_with?("\e7", "\e8")
        text.start_with?("\e7") ? @saved = [@row, @col] : (@row, @col = @saved)
        text = text[2..]
      else
        char = text[0]
        text = text[1..]
        character(char)
      end
    end
  end

  def character(char)
    case char
    when "\n" then (@row += 1) && (@col = 0)
    when "\r" then @col = 0
    when "\e" then nil
    else
      row[@col] = char
      @col += 1
    end
  end

  def control(params, final)
    n = params.to_i.zero? ? 1 : params.to_i
    case final
    when "A" then @row = [@row - n, 0].max
    when "B" then @row += n
    when "C" then @col += n
    when "D" then @col = [@col - n, 0].max
    when "G" then @col = n - 1
    when "K" then params == "2" ? row.clear : row.slice!(@col..)
    when "J" then (row.slice!(@col..)) && @rows.slice!(@row + 1..)
    end
  end

  def row
    @rows << [] while @rows.size <= @row
    @rows[@row]
  end
end
