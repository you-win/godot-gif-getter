use gdnative::prelude::*;
use std::fs::File;
use std::thread;

use gif::{Encoder, Frame, Repeat};

#[derive(NativeClass)]
#[inherit(Reference)]
#[user_data(user_data::MutexData<GifHandler>)]
pub struct GifHandler {
    pub file_name: String,
}

#[methods]
impl GifHandler {
    fn new(_owner: &Reference) -> Self {
        GifHandler {
            file_name: "".to_owned(),
        }
    }

    #[export]
    fn set_file_name(&mut self, _owner: &Reference, new_name: GodotString) {
        self.file_name = new_name.to_string();
    }

    #[export]
    fn write_frame(&self, _owner: &Reference, _image_data: ByteArray) {}

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
            let frame = Frame::from_rgba_speed(width, height, bytes.write().as_mut_slice(), 10);
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
            threads.push(thread::spawn(move || {
                let mut result = vec![];
                for buffer in buffers {
                    godot_print!("processing frame");
                    let mut bytes = buffer.to_byte_array();
                    let frame =
                        Frame::from_rgba_speed(width, height, bytes.write().as_mut_slice(), 10);
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
        }

        let mut image = File::create(&self.file_name).unwrap();
        let mut encoder = Encoder::new(&mut image, width, height, &[]).unwrap();
        encoder.set_repeat(Repeat::Infinite).unwrap();
        for rr in reordered_result {
            encoder.write_frame(&rr).unwrap();
        }
    }

    // TODO does not work, returns buffer indices instead of actual buffer data
    #[export]
    fn get_buffers(
        &self,
        _owner: &Reference,
        array_of_bytes: VariantArray,
        width: u16,
        height: u16,
        thread_count: u16,
    ) -> VariantArray {
        let result = VariantArray::new();

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
            threads.push(thread::spawn(move || {
                let result = VariantArray::new();
                for buffer in buffers {
                    godot_print!("processing frame");
                    let mut bytes = buffer.to_byte_array();
                    let frame =
                        Frame::from_rgba_speed(width, height, bytes.write().as_mut_slice(), 10);
                    let mut byte_array = ByteArray::new();
                    byte_array.append_vec(&mut frame.buffer.to_vec());
                    result.push(byte_array);
                }
                return result;
            }));
        }

        for t in threads {
            let thread_result = t.join().unwrap();
            result.push(thread_result);
        }

        return result.into_shared();
    }
}
