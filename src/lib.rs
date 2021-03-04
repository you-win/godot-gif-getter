use gdnative::prelude::*;

mod gif_handler;

fn init(handle: InitHandle) {
    handle.add_class::<gif_handler::GifHandler>();
}

godot_init!(init);
