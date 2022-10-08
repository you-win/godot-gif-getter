use gdnative::prelude::*;
use std::fs::File;
use std::thread;

use gif::{Encoder, Frame, Repeat};

#[derive(NativeClass)]
#[inherit(Reference)]
#[user_data(user_data::MutexData<GifHandler>)]
pub struct GifHandler {
    file_name: String,
    frame_delay: u16,
    render_quality: i32,

    parent: Variant,
}

#[methods]
impl GifHandler {
    fn new(_owner: &Reference) -> Self {
        GifHandler {
            file_name: "".to_owned(),
            frame_delay: 10,
            render_quality: 10,

            parent: Variant::new(),
        }
    }

    #[export]
    fn set_file_name(&mut self, _owner: &Reference, name: GodotString) {
        self.file_name = name.to_string();
    }

    #[export]
    fn set_frame_delay(&mut self, _owner: &Reference, frame_delay: u16) {
        self.frame_delay = frame_delay;
    }

    #[export]
    fn set_render_quality(&mut self, _owner: &Reference, render_quality: i32) {
        self.render_quality = render_quality;
    }

    #[export]
    fn set_parent(&mut self, _owner: &Reference, parent: Variant) {
        self.parent = parent;
    }

    #[export]
    fn write_frames_single_threaded(
        &self,
        _owner: &Reference,
        array_of_bytes: VariantArray,
        width: u16,
        height: u16,
    ) {
        let mut image = File::create(&self.file_name).unwrap();
        let mut encoder = Encoder::new(&mut image, width, height, &[]).unwrap();
        encoder.set_repeat(Repeat::Infinite).unwrap();
        for image in array_of_bytes.iter() {
            godot_print!("processed frame");
            let mut bytes = image.to_byte_array();
            let mut frame = Frame::from_rgba_speed(width, height, bytes.write().as_mut_slice(), self.render_quality);
            frame.delay = self.frame_delay / 10; // in units of 10ms
            encoder.write_frame(&frame).unwrap();
        }
    }

    #[export]
    fn write_frames(
        &self,
        _owner: &Reference,
        array_of_bytes: VariantArray,
        width: u16,
        height: u16,
        thread_count: u16,
        max_frames: u16,
    ) {
        if self.file_name == "" || self.parent == Variant::new() {
            godot_print!("Missing required fields. Did you remember to call set_file_name(...) and set_parent(...)?");
            return;
        }

        let mut threads = vec![];
        let mut separated_buffers = vec![];
        for _i in 0..thread_count {
            separated_buffers.push(vec![]);
        }

        let mut c = 0;
        for bytes in array_of_bytes.iter() {
            separated_buffers[c].push(bytes);
            if c < (thread_count - 1).into() {
                c += 1;
            } else {
                c = 0;
            }
        }

        for i in 0..thread_count {
            let index: usize = i.into();
            let buffers = separated_buffers[index].to_vec();
            let parent = self.parent.clone();
            let render_quality = self.render_quality.clone();
            let frame_delay = self.frame_delay;
            threads.push(thread::spawn(move || {
                let thread_name = (i + 1).to_string();
                let mut result = vec![];
                for (buffer_index, buffer) in buffers.iter().enumerate() {
                    log_message(
                        parent.clone(),
                        format!(
                            "thread {name} processing frame {buffer_count}",
                            name = thread_name,
                            buffer_count = buffer_index + 1
                        ),
                    );
                    let mut bytes = buffer.to_byte_array();
                    let mut frame = Frame::from_rgba_speed(
                        width,
                        height,
                        bytes.write().as_mut_slice(),
                        render_quality,
                    );
                    frame.delay = frame_delay / 10; // in units of 10ms
                    result.push(frame);
                }
                return result;
            }));
        }

        let mut result = vec![];
        for t in threads {
            let mut thread_result = t.join().unwrap();
            thread_result.reverse();
            result.push(thread_result);
        }

        let mut reordered_result = vec![];
        c = 0;
        for _r in 0..max_frames {
            let frame = result[c].pop();
            match frame {
                Some(f) => reordered_result.push(f),
                None => {}
            }
            if c < (thread_count - 1).into() {
                c += 1;
            } else {
                c = 0;
            }
        }

        let mut image = File::create(&self.file_name).unwrap();
        let mut encoder = Encoder::new(&mut image, width, height, &[]).unwrap();
        encoder.set_repeat(Repeat::Infinite).unwrap();
        for (rr_i, rr) in reordered_result.iter().enumerate() {
            log_message(
                self.parent.clone(),
                format!("Writing frame {frame_index}", frame_index = rr_i + 1),
            );
            encoder.write_frame(&rr).unwrap();
        }
    }
}

fn log_message(mut v: Variant, message: String) {
    let variant_message = Variant::from_godot_string(&GodotString::from_str(message.to_string()));
    v.call("_log_message", &[variant_message]).unwrap();
}
