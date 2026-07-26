//! Terminal formatting: colors, truncation, byte-safe excerpts.

use std::io::IsTerminal;
use std::sync::LazyLock;

static COLOR: LazyLock<bool> =
    LazyLock::new(|| std::io::stdout().is_terminal() && std::env::var_os("NO_COLOR").is_none());

pub const RESET: &str = "\x1b[0m";
pub const DIM: &str = "\x1b[2m";
pub const BOLD: &str = "\x1b[1m";
pub const GREEN: &str = "\x1b[32m";
pub const YELLOW: &str = "\x1b[33m";
pub const RED: &str = "\x1b[31m";
pub const CYAN: &str = "\x1b[36m";

/// Wrap `s` in an ANSI code, or return it untouched when colors are off.
pub fn paint(code: &str, s: &str) -> String {
    if *COLOR {
        format!("{code}{s}{RESET}")
    } else {
        s.to_string()
    }
}

pub fn status_color(status: u16) -> &'static str {
    match status {
        200..=299 => GREEN,
        300..=399 => CYAN,
        400..=499 => YELLOW,
        _ => RED,
    }
}

/// Truncate to `max` display characters, with the final character an ellipsis.
pub fn truncate(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        return s.to_string();
    }
    let head: String = s.chars().take(max.saturating_sub(1)).collect();
    format!("{head}…")
}

/// First `max` bytes of a response body, decoded lossily.
///
/// Slicing bytes first can land mid-codepoint; the lossy decode turns that
/// tail into a replacement character instead of panicking.
pub fn body_excerpt(bytes: &[u8], max: usize) -> String {
    String::from_utf8_lossy(&bytes[..bytes.len().min(max)]).into_owned()
}

/// Print a left-aligned table. `rows` must all have `headers.len()` columns.
pub fn table(headers: &[&str], rows: &[Vec<String>]) {
    let mut widths: Vec<usize> = headers.iter().map(|h| h.chars().count()).collect();
    for row in rows {
        for (i, cell) in row.iter().enumerate() {
            widths[i] = widths[i].max(cell.chars().count());
        }
    }
    let line = |cells: &[String]| {
        let mut out = String::new();
        for (i, cell) in cells.iter().enumerate() {
            let pad = widths[i] - cell.chars().count();
            out.push_str(cell);
            if i + 1 < cells.len() {
                out.push_str(&" ".repeat(pad + 2));
            }
        }
        out
    };
    let head: Vec<String> = headers.iter().map(|h| h.to_string()).collect();
    println!("{}", paint(DIM, &line(&head)));
    for row in rows {
        println!("{}", line(row));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn truncate_leaves_short_strings_alone() {
        assert_eq!(truncate("/wh", 40), "/wh");
        assert_eq!(truncate("abcde", 5), "abcde");
    }

    #[test]
    fn truncate_appends_ellipsis() {
        assert_eq!(truncate("abcdef", 5), "abcd…");
        assert_eq!(truncate("abcdef", 5).chars().count(), 5);
    }

    #[test]
    fn truncate_counts_characters_not_bytes() {
        // Six multibyte characters, well over six bytes.
        assert_eq!(truncate("ααααα", 3), "αα…");
    }

    #[test]
    fn body_excerpt_does_not_panic_mid_codepoint() {
        let s = "aé漢字🎉".repeat(10);
        for max in 0..s.len() + 5 {
            let out = body_excerpt(s.as_bytes(), max);
            assert!(out.len() <= max.max(3) + 3);
        }
    }

    #[test]
    fn body_excerpt_truncates_on_byte_boundary_count() {
        // "é" is two bytes: one byte in, we get a replacement character.
        assert_eq!(body_excerpt("é".as_bytes(), 1), "\u{fffd}");
        assert_eq!(body_excerpt("é".as_bytes(), 2), "é");
        assert_eq!(body_excerpt(b"hello", 10), "hello");
    }
}
