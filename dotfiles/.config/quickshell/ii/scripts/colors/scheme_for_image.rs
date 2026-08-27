//! Pick a Material colour-scheme family from an image without Python/OpenCV.
//!
//! ImageMagick performs format decoding and the resize that the wallpaper stack
//! already needs elsewhere. This helper consumes its compact PPM output and
//! computes the Hasler/Suesstrunk colourfulness metric in one native process.

use std::env;
use std::io::{self, Write};
use std::process::{Command, ExitCode, Stdio};

fn skip_space_and_comments(data: &[u8], cursor: &mut usize) {
    loop {
        while *cursor < data.len() && data[*cursor].is_ascii_whitespace() {
            *cursor += 1;
        }
        if *cursor >= data.len() || data[*cursor] != b'#' {
            return;
        }
        while *cursor < data.len() && data[*cursor] != b'\n' {
            *cursor += 1;
        }
    }
}

fn token<'a>(data: &'a [u8], cursor: &mut usize) -> Result<&'a [u8], String> {
    skip_space_and_comments(data, cursor);
    let start = *cursor;
    while *cursor < data.len() && !data[*cursor].is_ascii_whitespace() {
        *cursor += 1;
    }
    if start == *cursor {
        return Err("truncated PPM header".into());
    }
    Ok(&data[start..*cursor])
}

fn parse_usize(value: &[u8], field: &str) -> Result<usize, String> {
    std::str::from_utf8(value)
        .map_err(|_| format!("invalid {field}"))?
        .parse::<usize>()
        .map_err(|_| format!("invalid {field}"))
}

fn ppm_pixels(data: &[u8]) -> Result<&[u8], String> {
    let mut cursor = 0;
    if token(data, &mut cursor)? != b"P6" {
        return Err("ImageMagick returned an unsupported PPM encoding".into());
    }
    let width = parse_usize(token(data, &mut cursor)?, "width")?;
    let height = parse_usize(token(data, &mut cursor)?, "height")?;
    let maximum = parse_usize(token(data, &mut cursor)?, "channel depth")?;
    if maximum != 255 {
        return Err(format!("unsupported PPM channel depth: {maximum}"));
    }
    if cursor >= data.len() || !data[cursor].is_ascii_whitespace() {
        return Err("missing PPM pixel delimiter".into());
    }
    cursor += 1;

    let expected = width
        .checked_mul(height)
        .and_then(|pixels| pixels.checked_mul(3))
        .ok_or_else(|| "image dimensions overflow".to_string())?;
    if data.len().saturating_sub(cursor) < expected {
        return Err("truncated PPM pixel data".into());
    }
    Ok(&data[cursor..cursor + expected])
}

fn colorfulness(pixels: &[u8]) -> Result<f64, String> {
    if pixels.is_empty() || !pixels.len().is_multiple_of(3) {
        return Err("invalid RGB pixel data".into());
    }

    let count = (pixels.len() / 3) as f64;
    let mut sum_rg = 0.0;
    let mut sum_yb = 0.0;
    let mut sum_sq_rg = 0.0;
    let mut sum_sq_yb = 0.0;

    for rgb in pixels.chunks_exact(3) {
        let red = f64::from(rgb[0]);
        let green = f64::from(rgb[1]);
        let blue = f64::from(rgb[2]);
        let rg = (red - green).abs();
        let yb = (0.5 * (red + green) - blue).abs();
        sum_rg += rg;
        sum_yb += yb;
        sum_sq_rg += rg * rg;
        sum_sq_yb += yb * yb;
    }

    let mean_rg = sum_rg / count;
    let mean_yb = sum_yb / count;
    let std_rg = (sum_sq_rg / count - mean_rg * mean_rg).max(0.0).sqrt();
    let std_yb = (sum_sq_yb / count - mean_yb * mean_yb).max(0.0).sqrt();
    Ok((std_rg * std_rg + std_yb * std_yb).sqrt()
        + 0.3 * (mean_rg * mean_rg + mean_yb * mean_yb).sqrt())
}

fn run() -> Result<(), String> {
    let mut image_path = None;
    let mut print_score = false;
    for argument in env::args().skip(1) {
        if argument == "--colorfulness" {
            print_score = true;
        } else if image_path.replace(argument).is_some() {
            return Err("usage: scheme-for-image [--colorfulness] IMAGE".into());
        }
    }
    let image_path = image_path
        .ok_or_else(|| "usage: scheme-for-image [--colorfulness] IMAGE".to_string())?;

    let output = Command::new("magick")
        .args([
            image_path.as_str(),
            "-auto-orient",
            "-thumbnail",
            "128x128>",
            "-depth",
            "8",
            "ppm:-",
        ])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .map_err(|error| format!("could not start ImageMagick: {error}"))?;
    if !output.status.success() {
        return Err("ImageMagick could not decode the image".into());
    }

    let score = colorfulness(ppm_pixels(&output.stdout)?)?;
    if print_score {
        println!("{score}");
    } else if score < 40.0 {
        println!("scheme-neutral");
    } else {
        println!("scheme-tonal-spot");
    }
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            let _ = writeln!(io::stderr(), "scheme-for-image: {message}");
            ExitCode::FAILURE
        }
    }
}
