import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import struct
import os
from typing import List, Dict, Tuple, Optional
import binascii

class CartridgeChip:
    def __init__(self, chip_type: int, bank_number: int, start_address: int, rom_size: int, data: bytes):
        self.chip_type = chip_type
        self.bank_number = bank_number
        self.start_address = start_address
        self.rom_size = rom_size
        self.data = data
    
    def __str__(self) -> str:
        return f"Chip Type: {self.chip_type}, Bank: {self.bank_number}, Address: ${self.start_address:04X}, Size: {self.rom_size} bytes"

class Cartridge:
    def __init__(self):
        self.version = 0
        self.hardware_type = 0
        self.exrom = 0
        self.game = 0
        self.name = ""
        self.chips: List[CartridgeChip] = []
        self.filename = ""
        
        # Hardware type names according to the CRT format spec
        self.hardware_types = {
            0: "Generic cartridge",
            1: "Action Replay",
            2: "KCS Power Cartridge",
            3: "Final Cartridge III",
            4: "Simons' BASIC",
            5: "Ocean type 1",
            6: "Expert Cartridge",
            7: "Fun Play, Power Play",
            8: "Super Games",
            9: "Atomic Power",
            10: "Epyx Fastload",
            11: "Westermann Learning",
            12: "Rex Utility",
            13: "Final Cartridge I",
            14: "Magic Formel",
            15: "C64 Game System, System 3",
            16: "Warp Speed",
            17: "Dinamic",
            18: "Zaxxon, Super Zaxxon (SEGA)",
            19: "Magic Desk, Domark, HES Australia",
            20: "Super Snapshot V5",
            21: "Comal-80",
            22: "Structured BASIC",
            23: "Ross",
            24: "Dela EP64",
            25: "Dela EP7x8",
            26: "Dela EP256",
            27: "Rex EP256",
            28: "Mikro Assembler",
            29: "Final Cartridge Plus",
            30: "Action Replay 4",
            31: "Stardos",
            32: "EasyFlash",
            33: "EasyFlash Xbank",
            34: "Capture",
            35: "Action Replay 3",
            36: "Retro Replay",
            37: "MMC64",
            38: "MMC Replay",
            39: "IDE64",
            40: "Super Snapshot V4",
            41: "IEEE-488",
            42: "Game Killer",
            43: "Prophet64",
            44: "EXOS",
            45: "Freeze Frame",
            46: "Freeze Machine",
            47: "Snapshot 64",
            48: "Super Explode V5.0",
            49: "Magic Voice",
            50: "Action Replay 2",
            51: "MACH 5",
            52: "Diashow-Maker",
            53: "Pagefox",
            54: "Kingsoft",
            55: "Silverrock 128K Cartridge",
            56: "Formel 64",
            57: "RGCD",
            58: "RR-Net MK3",
            59: "EasyCalc",
            60: "GMod2",
            61: "Max Basic",
            62: "GMod3",
            63: "ZIPP-CODE 48",
            64: "Blackbox V8",
            65: "Blackbox V3",
            66: "Blackbox V4",
            67: "REX RAM-Floppy",
            68: "BIS-Plus",
            69: "SD-BOX",
            70: "MultiMAX",
            71: "Blackbox V9",
            72: "Lt. Kernal Host Adaptor",
            73: "RAMLink",
            74: "HERO",
            75: "IEEE Flash! 64",
            76: "Retro Gold",
            77: "GeoRAM",
            78: "ISEPIC",
            79: "Drean",
            80: "Dinamic with Aladdin",
            81: "Sega System E",
            82: "TurboTape"
        }
    
    def load(self, filename: str) -> bool:
        try:
            self.filename = os.path.basename(filename)
            with open(filename, 'rb') as f:
                # Read and verify the signature
                signature = f.read(16)
                if signature != b'C64 CARTRIDGE   ':
                    messagebox.showerror("Error", "Not a valid CRT file (missing C64 CARTRIDGE signature)")
                    return False
                
                # Read header length (usually 0x00000040 = 64 bytes)
                header_length = struct.unpack('>I', f.read(4))[0]
                
                # Read version
                self.version = struct.unpack('>H', f.read(2))[0]
                
                # Read hardware type
                self.hardware_type = struct.unpack('>H', f.read(2))[0]
                
                # Read EXROM and GAME lines
                self.exrom = f.read(1)[0]
                self.game = f.read(1)[0]
                
                # Skip reserved bytes
                f.read(2)
                
                # Read cartridge name
                name_bytes = f.read(16)
                self.name = name_bytes.split(b'\0')[0].decode('utf-8', errors='replace')
                
                # Skip remaining header bytes
                f.read(header_length - 0x2C)  # 0x2C = 44 bytes read so far
                
                # Read all CHIP blocks
                self.chips = []
                while True:
                    # Try to read CHIP signature
                    chip_sig = f.read(4)
                    if not chip_sig or len(chip_sig) < 4:
                        break
                    
                    if chip_sig != b'CHIP':
                        messagebox.showerror("Error", f"Invalid CHIP signature: {chip_sig}")
                        return False
                    
                    # Read total packet length
                    packet_length = struct.unpack('>I', f.read(4))[0]
                    
                    # Read chip type
                    chip_type = struct.unpack('>H', f.read(2))[0]
                    
                    # Read bank number
                    bank_number = struct.unpack('>H', f.read(2))[0]
                    
                    # Read start address
                    start_address = struct.unpack('>H', f.read(2))[0]
                    
                    # Read ROM size
                    rom_size = struct.unpack('>H', f.read(2))[0]
                    
                    # Read the ROM data
                    rom_data = f.read(packet_length - 16)  # 16 bytes of header already read
                    
                    # Create and add the chip
                    chip = CartridgeChip(chip_type, bank_number, start_address, rom_size, rom_data)
                    self.chips.append(chip)
                
                return True
            
        except Exception as e:
            messagebox.showerror("Error", f"Failed to load CRT file: {str(e)}")
            return False
    
    def get_hardware_type_name(self) -> str:
        return self.hardware_types.get(self.hardware_type, f"Unknown Type ({self.hardware_type})")

class HexViewer(tk.Frame):
    def __init__(self, parent, **kwargs):
        super().__init__(parent, **kwargs)
        self.text = tk.Text(self, font=("Courier", 10), wrap=tk.NONE, height=25, width=80)
        
        self.scrollbar_y = tk.Scrollbar(self, orient=tk.VERTICAL, command=self.text.yview)
        self.text.configure(yscrollcommand=self.scrollbar_y.set)
        
        self.scrollbar_x = tk.Scrollbar(self, orient=tk.HORIZONTAL, command=self.text.xview)
        self.text.configure(xscrollcommand=self.scrollbar_x.set)
        
        # Status bar for showing decimal values
        self.status_var = tk.StringVar()
        self.status_bar = tk.Label(self, textvariable=self.status_var, anchor=tk.W, bd=1, relief=tk.SUNKEN)
        
        # Grid layout
        self.text.grid(row=0, column=0, sticky="nsew")
        self.scrollbar_y.grid(row=0, column=1, sticky="ns")
        self.scrollbar_x.grid(row=1, column=0, sticky="ew")
        self.status_bar.grid(row=2, column=0, columnspan=2, sticky="ew")
        
        self.grid_rowconfigure(0, weight=1)
        self.grid_columnconfigure(0, weight=1)
        
        # Tags for highlighting
        self.text.tag_configure("header", foreground="blue", font=("Courier", 10, "bold"))
        self.text.tag_configure("hex", foreground="black")
        self.text.tag_configure("ascii", foreground="green")
        self.text.tag_configure("address", foreground="purple")
        
        # Setup hover binding
        self.text.tag_bind("hex_value", "<Enter>", self.on_hex_hover)
        self.text.tag_bind("hex_value", "<Leave>", self.on_hex_leave)
        
        self.current_chip = None
        self.hex_positions = {}  # Maps (row, col) -> (byte_offset, hex_value)
    
    def set_data(self, chip: CartridgeChip):
        self.current_chip = chip
        self.text.delete(1.0, tk.END)
        self.hex_positions = {}
        
        self.text.insert(tk.END, f"Chip Type: {chip.chip_type}, Bank: {chip.bank_number}, " + 
                         f"Start Address: ${chip.start_address:04X}, Size: {chip.rom_size} bytes\n\n", "header")
        
        # Calculate base address for this bank
        base_address = chip.bank_number * 0x2000 + chip.start_address
        
        # Display hex data in rows of 16 bytes
        for offset in range(0, len(chip.data), 16):
            # Address display
            addr_str = f"{base_address + offset:06X} ({offset:04X}): "
            self.text.insert(tk.END, addr_str, "address")
            
            # Hex display
            for i in range(16):
                if offset + i < len(chip.data):
                    byte_val = chip.data[offset + i]
                    hex_str = f"{byte_val:02X} "
                    
                    # Save position of this hex value
                    pos = self.text.index(tk.END)
                    line, col = map(int, pos.split('.'))
                    
                    self.text.insert(tk.END, hex_str, ("hex", f"hex_value"))
                    
                    # Save mapping of text position to byte info
                    self.hex_positions[(line-1, col)] = (offset + i, byte_val)
                else:
                    self.text.insert(tk.END, "   ", "hex")
            
            # ASCII display
            self.text.insert(tk.END, " | ", "hex")
            for i in range(16):
                if offset + i < len(chip.data):
                    byte_val = chip.data[offset + i]
                    # Only printable ASCII
                    char = chr(byte_val) if 32 <= byte_val <= 126 else '.'
                    self.text.insert(tk.END, char, "ascii")
                else:
                    self.text.insert(tk.END, " ", "ascii")
            
            self.text.insert(tk.END, "\n")
    
    def on_hex_hover(self, event):
        index = self.text.index(f"@{event.x},{event.y}")
        line, col = map(int, index.split('.'))
        
        # Find the closest hex value position
        for pos_col in range(col, col - 3, -1):
            if (line, pos_col) in self.hex_positions:
                offset, value = self.hex_positions[(line, pos_col)]
                
                # Calculate global address
                global_addr = self.current_chip.bank_number * 0x2000 + self.current_chip.start_address + offset
                
                # Update status bar
                self.status_var.set(f"Offset: {offset} (0x{offset:04X}), Value: {value} (0x{value:02X}), " +
                                    f"Global Address: 0x{global_addr:06X}")
                return
        
        # If no hex value found, clear status
        self.status_var.set("")
        
    def on_hex_leave(self, event):
        self.status_var.set("")


class BankChipVisualizer(tk.Canvas):
    def __init__(self, parent, **kwargs):
        super().__init__(parent, **kwargs)
        self.chips = []
        self.chip_rectangles = {}  # Maps canvas rectangles to chips
        self.callback = None

        # Bind click event
        self.bind("<Button-1>", self.on_click)

        # Bind configure event to handle resize
        self.bind("<Configure>", self.on_resize)

        # Bind mouse wheel events for scrolling
        self.bind("<MouseWheel>", self.on_mousewheel)  # Windows
        self.bind("<Button-4>", self.on_mousewheel)  # Linux scroll up
        self.bind("<Button-5>", self.on_mousewheel)  # Linux scroll down

    def on_resize(self, event):
        # Redraw when canvas is resized
        if hasattr(self, 'chips'):
            self.redraw()

    def set_chips(self, chips: List[CartridgeChip], callback=None):
        self.chips = chips
        self.callback = callback
        self.redraw()

    def redraw(self):
        self.delete("all")
        self.chip_rectangles = {}

        if not self.chips:
            self.create_text(self.winfo_width() // 2, self.winfo_height() // 2,
                             text="No cartridge loaded", fill="gray")
            self.configure(scrollregion=self.bbox("all"))
            return

        # Find all unique banks
        banks = sorted(list(set(chip.bank_number for chip in self.chips)))

        # Calculate layout
        margin = 20
        bank_height = 40
        chip_height = 30
        chip_spacing = 10
        bank_spacing = 20

        # Get max bank for width calculation
        max_bank = max(banks) if banks else 0
        canvas_width = max(self.winfo_width(), (max_bank + 1) * 100 + 2 * margin)

        # Draw title
        self.create_text(canvas_width // 2, margin,
                         text="Cartridge Memory Map", font=("Arial", 14, "bold"))

        # Draw banks and chips
        y_pos = margin + 30
        max_y = y_pos

        for bank in banks:
            # Draw bank
            bank_width = 80
            bank_x = margin
            self.create_rectangle(bank_x, y_pos, bank_x + bank_width, y_pos + bank_height,
                                  fill="lightblue", outline="blue")
            self.create_text(bank_x + bank_width // 2, y_pos + bank_height // 2,
                             text=f"Bank {bank}")

            # Draw chips in this bank
            bank_chips = [chip for chip in self.chips if chip.bank_number == bank]
            chip_x = bank_x + bank_width + 20

            # Track max width for this row
            row_max_x = chip_x

            for chip in bank_chips:
                # Chip width based on its size
                chip_width = min(600, max(100, chip.rom_size / 256))

                # Create chip rectangle with tag for identification
                chip_tag = f"chip_{bank}_{chip.start_address}"
                rect_id = self.create_rectangle(chip_x, y_pos, chip_x + chip_width, y_pos + chip_height,
                                                fill="lightgreen", outline="green", activefill="palegreen",
                                                tags=(chip_tag))
                self.chip_rectangles[rect_id] = chip

                # Add text with the same tag
                self.create_text(chip_x + chip_width // 2, y_pos + chip_height // 2,
                                 text=f"${chip.start_address:04X}: {chip.rom_size} bytes",
                                 tags=(chip_tag))

                # Bind events to the tag
                self.tag_bind(chip_tag, "<Button-1>",
                              lambda event, chip=chip: self.on_chip_click(event, chip))

                chip_x += chip_width + 20
                row_max_x = max(row_max_x, chip_x)

            y_pos += bank_height + bank_spacing
            max_y = y_pos
            canvas_width = max(canvas_width, row_max_x)

        # Update the scroll region to encompass all objects
        # Add small padding to prevent unnecessary scrolling
        self.configure(scrollregion=(0, 0, canvas_width + margin, max_y))

    def on_chip_click(self, event, chip):
        if self.callback:
            self.callback(chip)

    def on_click(self, event):
        # This is now handled by the tag bindings
        pass

    def on_mousewheel(self, event):
        """Handle mouse wheel scrolling."""
        # Different event handling for Windows vs Linux
        if event.num == 4 or event.delta > 0:
            # Scroll up
            self.yview_scroll(-1, "units")
        elif event.num == 5 or event.delta < 0:
            # Scroll down
            self.yview_scroll(1, "units")


class CartridgeVisualizerApp:
    def __init__(self, root):
        self.root = root
        self.root.title("C64 Cartridge Visualizer")
        self.root.geometry("1400x700")  # Larger window size

        self.cartridge = Cartridge()

        # Create main frame
        self.main_frame = ttk.Frame(root)
        self.main_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        # Create menubar
        self.menubar = tk.Menu(root)
        root.config(menu=self.menubar)

        # File menu
        self.file_menu = tk.Menu(self.menubar, tearoff=0)
        self.file_menu.add_command(label="Open CRT File", command=self.open_file)
        self.file_menu.add_command(label="Reload", command=self.reload_file, state=tk.DISABLED)
        self.file_menu.add_separator()
        self.file_menu.add_command(label="Exit", command=root.quit)
        self.menubar.add_cascade(label="File", menu=self.file_menu)

        # Create toolbar
        self.toolbar = ttk.Frame(self.main_frame)
        self.toolbar.pack(fill=tk.X, pady=(0, 5))

        # Add buttons to toolbar
        self.open_button = ttk.Button(self.toolbar, text="Open", command=self.open_file)
        self.open_button.pack(side=tk.LEFT, padx=2)

        self.reload_button = ttk.Button(self.toolbar, text="Reload", command=self.reload_file, state=tk.DISABLED)
        self.reload_button.pack(side=tk.LEFT, padx=2)

        # Create info frame
        self.info_frame = ttk.LabelFrame(self.main_frame, text="Cartridge Info")
        self.info_frame.pack(fill=tk.X, pady=5)

        # Create info labels
        self.info_labels = {}
        info_fields = [
            ("filename", "File:"),
            ("name", "Name:"),
            ("hardware_type", "Hardware Type:"),
            ("version", "Version:"),
            ("exrom_game", "EXROM/GAME:"),
            ("chip_count", "Chips:")
        ]

        for row, (field, label) in enumerate(info_fields):
            ttk.Label(self.info_frame, text=label, width=15).grid(row=row, column=0, sticky=tk.W, padx=5, pady=2)
            self.info_labels[field] = ttk.Label(self.info_frame, text="", width=50)
            self.info_labels[field].grid(row=row, column=1, sticky=tk.W, padx=5, pady=2)

        # Create paned window for split view
        self.paned_window = ttk.PanedWindow(self.main_frame, orient=tk.HORIZONTAL)
        self.paned_window.pack(fill=tk.BOTH, expand=True, pady=5)

        # Frame for banks/chips visualization
        self.bank_frame = ttk.LabelFrame(self.paned_window, text="Banks & Chips")

        # Frame for chip content
        self.chip_frame = ttk.LabelFrame(self.paned_window, text="Chip Content")

        # Add frames to paned window
        self.paned_window.add(self.bank_frame, weight=1)
        self.paned_window.add(self.chip_frame, weight=1)

        # Create bank/chip visualizer with scrolling support
        self.bank_visualizer_frame = ttk.Frame(self.bank_frame)
        self.bank_visualizer_frame.pack(fill=tk.BOTH, expand=True)

        # Create scrollbars for bank visualizer
        self.bank_y_scrollbar = tk.Scrollbar(self.bank_visualizer_frame, orient=tk.VERTICAL)
        self.bank_x_scrollbar = tk.Scrollbar(self.bank_frame, orient=tk.HORIZONTAL)

        # Create bank visualizer
        self.bank_visualizer = BankChipVisualizer(self.bank_visualizer_frame, bg="white",
                                                  width=500, height=500)

        # Configure scrollbar connections
        self.bank_visualizer.configure(yscrollcommand=self.bank_y_scrollbar.set,
                                       xscrollcommand=self.bank_x_scrollbar.set)
        self.bank_y_scrollbar.configure(command=self.bank_visualizer.yview)
        self.bank_x_scrollbar.configure(command=self.bank_visualizer.xview)

        # Pack components with correct layout
        self.bank_visualizer.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.bank_y_scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.bank_x_scrollbar.pack(side=tk.BOTTOM, fill=tk.X)

        # Set callback for chip selection
        self.bank_visualizer.set_chips([], self.on_chip_selected)

        # Create hex viewer
        self.hex_viewer = HexViewer(self.chip_frame)
        self.hex_viewer.pack(fill=tk.BOTH, expand=True)

        # Status bar
        self.status_var = tk.StringVar()
        self.status_var.set("Ready")
        self.status_bar = ttk.Label(root, textvariable=self.status_var, anchor=tk.W,
                                   relief=tk.SUNKEN)
        self.status_bar.pack(side=tk.BOTTOM, fill=tk.X)

        # Initial UI state
        self.update_ui()

    def open_file(self):
        file_path = filedialog.askopenfilename(
            filetypes=[("CRT Files", "*.crt"), ("All Files", "*.*")]
        )

        if file_path:
            self.status_var.set(f"Loading {os.path.basename(file_path)}...")
            self.root.update_idletasks()

            # Store the full path for reload functionality
            self._last_full_path = file_path

            if self.cartridge.load(file_path):
                # Enable reload functionality
                self.file_menu.entryconfig("Reload", state=tk.NORMAL)
                self.reload_button.config(state=tk.NORMAL)

                self.update_ui()
                self.status_var.set(f"Loaded {os.path.basename(file_path)}")

                # Automatically select first chip if available
                if self.cartridge.chips:
                    self.on_chip_selected(self.cartridge.chips[0])
            else:
                self.status_var.set("Failed to load cartridge file")

    def reload_file(self):
        if hasattr(self.cartridge, 'filename') and self.cartridge.filename:
            full_path = None
            # Find the full path based on the filename
            if hasattr(self, '_last_full_path') and os.path.exists(self._last_full_path):
                full_path = self._last_full_path

            if full_path:
                self.status_var.set(f"Reloading {os.path.basename(full_path)}...")
                self.root.update_idletasks()

                if self.cartridge.load(full_path):
                    self.update_ui()
                    self.status_var.set(f"Reloaded {os.path.basename(full_path)}")

                    # Automatically select first chip if available
                    if self.cartridge.chips:
                        self.on_chip_selected(self.cartridge.chips[0])
                else:
                    self.status_var.set("Failed to reload cartridge file")
            else:
                messagebox.showerror("Error", "Unable to locate original file")

    def update_ui(self):
        # Update info labels
        self.info_labels["filename"].config(text=self.cartridge.filename or "No file loaded")
        self.info_labels["name"].config(text=self.cartridge.name or "N/A")
        self.info_labels["hardware_type"].config(text=self.cartridge.get_hardware_type_name())
        self.info_labels["version"].config(text=f"{self.cartridge.version}")
        self.info_labels["exrom_game"].config(text=f"EXROM={self.cartridge.exrom}, GAME={self.cartridge.game}")
        self.info_labels["chip_count"].config(text=f"{len(self.cartridge.chips)} chips")

        # Update bank/chip visualizer
        self.bank_visualizer.set_chips(self.cartridge.chips, self.on_chip_selected)

    def on_chip_selected(self, chip):
        # Update hex viewer with chip data
        self.hex_viewer.set_data(chip)
        self.status_var.set(f"Viewing chip: Bank {chip.bank_number}, Address ${chip.start_address:04X}, Size {chip.rom_size} bytes")


if __name__ == "__main__":
    root = tk.Tk()
    app = CartridgeVisualizerApp(root)
    root.mainloop()
