class Hiiro
  module TaskColors
    # 12 visually distinct, dark-background color pairs for tmux status bars.
    # All use colour255 (white) as foreground for readability.
    PALETTE = [
      { bg: 'colour24',  fg: 'colour255' },  # 0:  Steel blue
      { bg: 'colour88',  fg: 'colour255' },  # 1:  Dark red
      { bg: 'colour28',  fg: 'colour255' },  # 2:  Forest green
      { bg: 'colour130', fg: 'colour255' },  # 3:  Sienna
      { bg: 'colour54',  fg: 'colour255' },  # 4:  Purple
      { bg: 'colour23',  fg: 'colour255' },  # 5:  Dark teal
      { bg: 'colour52',  fg: 'colour255' },  # 6:  Crimson
      { bg: 'colour58',  fg: 'colour255' },  # 7:  Olive
      { bg: 'colour17',  fg: 'colour255' },  # 8:  Navy
      { bg: 'colour90',  fg: 'colour255' },  # 9:  Magenta
      { bg: 'colour94',  fg: 'colour255' },  # 10: Burnt orange
      { bg: 'colour22',  fg: 'colour255' },  # 11: Dark forest
    ].freeze

    def self.for_index(index)
      PALETTE[index.to_i % PALETTE.size]
    end

    # Apply status-bg / status-fg to the named tmux session.
    def self.apply(session_name, color_index)
      colors = for_index(color_index)
      Background.run('tmux', 'set-option', '-t', session_name, 'status-bg', colors[:bg])
      Background.run('tmux', 'set-option', '-t', session_name, 'status-fg', colors[:fg])
    end

    # Return the first palette index not already used by existing_indices,
    # falling back to modulo wrap-around when all colors are taken.
    def self.next_index(existing_indices)
      (0...PALETTE.size).find { |i| !existing_indices.include?(i) } ||
        (existing_indices.length % PALETTE.size)
    end
  end
end
