require "bit_array"
require "option_parser"

#The core CPU that will have the methods and IV's necessary to emulate the 6502 microprocessor
struct CPU
    #X register
    property reg_x : UInt8 = 0
    #Y register
    property reg_y : UInt8 = 0
    #Accumulator register
    property reg_a : UInt8 = 0
    #The program counter, which is used to indicate the next instruction to load from the program in memory.
    #This can be changed by using jump instructions, calling a subroutine, or exiting a subrouting or by an interrupt
    property program_counter : UInt16 = 0x0200
    #The pointer to the next place on the stack to be pushed. This starts at the top and moves downwards, starting at 0x01FF and ending at 0x0100.
    #This is an 8-bit register which holds the low 8 bits of the next location on the stack to be pushed to
    #When the stack is pushed, this decrements, when the stack is popped, it is incremented
    #This register does not handle overflows so overflows will have to be handled manually
    property stack_pointer : UInt8 = 0xff
    #The processor status holds bits specific to certain statuses of the processor
    #
    #The bits are as follows:
    #
    #```
    #   0 : Carry flag
    #   1 : Zero flag
    #   2 : Interrupt disable
    #   3 : Decimal mode
    #   4 : Break command
    #   5 : Overflow flag
    #   6 : Negative flag
    #```
    getter processor_status : BitArray = BitArray.new(7)
    #The memory of the cpu
    getter memory = Memory.new
    #The cycles remaining for the execution of an instruction.
    #Some instructions take more cycles than others, so after the first byte is fetched from memory using next_ins,
    #then there is 1 less cycle remaining for that instruction.
    #Example: LDX_IMM has 2 cycles, but after the first call to next_ins drops that down to 1, so when it's being processed, this will be set to 1
    property cycles_remaining = 0

    #Get the next instruction in memory without affecting the cycles remaining. This is mostly used for getting the first byte in an instruction, which would count as the first cycle of an instruction. This will increment the program counter
    def next_ins
        next_ins = self.memory[self.program_counter]
        self.program_counter += 1
        next_ins
    end

    #This is the same as next_ins except it decrements the cycles_remaining.
    def advance_next_ins
        next_ins = self.memory[self.program_counter]
        self.program_counter += 1
        self.cycles_remaining -= 1
        next_ins
    end

    #Push a byte onto the stack portion of memory. See Memory::data for more info on where the stack is in memory.
    #This counts as a cycle so when using this, make sure you have enough cycles set
    #Todo: Add assertion for cycles_remaining
    def stack_push(value : UInt8)
        self.memory[self.stack_pointer] = value
        self.stack_pointer -= 1
        self.cycles_remaining -= 1
    end

    #Push a word onto the stack. 
    #Because 6502 is in little endian, it will take the low byte then the high byte in that order on the stack
    def stack_push(value : UInt16)
        lower_byte = (value & 0x00FF).to_u8
        self.stack_push(lower_byte)
        higher_byte = ((value & 0xFF00) >> 8).to_u8
        self.stack_push(higher_byte)
    end

    #Pop a byte off the stack
    #
    #This will increment the stack pointer and decrement the cycles remaining
    #This will take up one cycle to complete
    #
    #This returns the value popped from the stack at stack_pointer + 1 
    def stack_pop
        value = self.memory[self.stack_pointer+1]
        self.stack_pointer += 1
        self.cycles_remaining -= 1
        value
    end
    
    #This will execute the loaded program by taking the first byte and 
    #decoding it as an instruction, and continuing to decode instructions until the next byte read is 0. 
    #If it fails to decode it, it will print an error.
    def execute
        ins = next_ins()
        until ins == 0
            case Instructions.new(ins)
            when Instructions::LDX_IMM
                self.cycles_remaining = 1
                value = advance_next_ins()
                self.reg_x = value
            when Instructions::LDX_ABS
                self.cycles_remaining = 3
                lower = (advance_next_ins() << 8).to_u16
                higher = advance_next_ins()
                address = lower | higher
                self.reg_x = self.memory[address]
                self.cycles_remaining -= 1
            when Instructions::LDX_ABS_Y
                self.cycles_remaining = 3
                lower = (advance_next_ins() << 8).to_u16
                higher = advance_next_ins()
                address = lower | higher
                self.reg_x = self.memory[address + self.reg_y]
                self.cycles_remaining -= 1
            when Instructions::LDX_ZERO
                self.cycles_remaining = 2
                adl = advance_next_ins()
                addr = (0x00 << 8).to_u16 | adl
                self.reg_x = self.memory[addr]
                self.cycles_remaining -= 1
            when Instructions::LDX_ZERO_Y
                self.cycles_remaining = 3
                adl = advance_next_ins()
                addr = (0x00 << 8).to_u16 | adl
                self.reg_x = self.memory[addr+self.reg_y]
                self.cycles_remaining -= 2
            when Instructions::STX_ZERO
                self.cycles_remaining = 2
                value = advance_next_ins()
                addr = (0x00 << 8).to_u16 | value
                self.memory[addr] = self.reg_x
                # puts "Storing X in address #{addr}"
                self.cycles_remaining -= 1
            when Instructions::STX_ZERO_Y
                self.cycles_remaining = 3
                value = advance_next_ins()
                addr = (0x00 << 8).to_u16 | value
                self.memory[addr+self.reg_y] = self.reg_x
                # puts "Storing X in address #{addr}"
                self.cycles_remaining -= 2
            when Instructions::STX_ABS
                self.cycles_remaining = 3
                adl = advance_next_ins()
                adh = advance_next_ins()
                addr = (adh << 8).to_u16 | adl
                self.memory[addr] = self.reg_x
                self.cycles_remaining -= 1
            when Instructions::LDY_IMM
                self.cycles_remaining = 1
                value = advance_next_ins()
                self.reg_y = value
            when Instructions::LDY_ZERO
                self.cycles_remaining = 2
                adl = advance_next_ins()
                addr = (0x00 << 8).to_u16 | adl
                self.reg_y = self.memory[addr]
                self.cycles_remaining -= 1
            when Instructions::LDY_ZERO_X
                self.cycles_remaining = 3
                adl = advance_next_ins()
                addr = (0x00 << 8).to_u16 | adl
                self.reg_y = self.memory[addr+self.reg_x]
                self.cycles_remaining -= 2
            when Instructions::LDY_ABS
                self.cycles_remaining = 3
                lower = (advance_next_ins() << 8).to_u16
                higher = advance_next_ins()
                address = lower | higher
                self.reg_y = self.memory[address]
                self.cycles_remaining -= 1
            when Instructions::LDY_ABS_X
                self.cycles_remaining = 4
                lower = (advance_next_ins() << 8).to_u16
                higher = advance_next_ins()
                address = lower | higher
                self.reg_y = self.memory[address+self.reg_x]
                self.cycles_remaining -= 2
            when Instructions::STY_ZERO
                self.cycles_remaining = 2
                value = advance_next_ins()
                addr = (0x00 << 8).to_u16 | value
                self.memory[addr] = self.reg_y
                self.cycles_remaining -= 1
            when Instructions::STY_ZERO_X
                self.cycles_remaining = 3
                value = advance_next_ins()
                addr = (0x00 << 8).to_u16 | value
                self.memory[addr+self.reg_x] = self.reg_y
                self.cycles_remaining -= 2
            when Instructions::STY_ABS
                self.cycles_remaining = 3
                adl = advance_next_ins()
                adh = advance_next_ins()
                addr = (adh << 8).to_u16 | adl
                self.memory[addr] = self.reg_y
                self.cycles_remaining -= 1
            when Instructions::JSR
                self.cycles_remaining = 6
                lower_byte = advance_next_ins()
                # puts "lower_byte: #{lower_byte.to_s(16)}"
                higher_byte = (advance_next_ins().to_u16 << 8).to_u16
                # puts "higher_byte: #{higher_byte.to_s(16)}"
                jump_target = (higher_byte | lower_byte).to_u16
                # puts "jump_target: #{jump_target.to_s(16)}"
                self.stack_push(self.program_counter - 1)
                self.program_counter = jump_target
                self.cycles_remaining -= 2
            when Instructions::RTS
                self.cycles_remaining = 5
                lower_byte = (self.stack_pop.to_u16).to_u16
                higher_byte = (self.stack_pop.to_u16 << 8).to_u16
                jump_target = (higher_byte | lower_byte).to_u16
                self.cycles_remaining -= 1
                self.program_counter = jump_target + 1
                self.cycles_remaining -= 2  #We decrement by two because we decrementing the jump target by 1 and that is two cycles
            when Instructions::LDA_IMM
                self.cycles_remaining = 1
                value = advance_next_ins()
                self.reg_a = value
            when Instructions::LDA_ZERO
                self.cycles_remaining = 2
                adl = advance_next_ins()
                addr = (0x00 << 8).to_u16 | adl
                self.reg_a = self.memory[addr]
                self.cycles_remaining -= 1
            when Instructions::LDA_ABS
                self.cycles_remaining = 3
                lower = (advance_next_ins() << 8).to_u16
                higher = advance_next_ins()
                address = lower | higher
                self.reg_a = self.memory[address]
            when Instructions::STA_ZERO
                self.cycles_remaining = 2
                adl = advance_next_ins()
                addr = (0x00 << 8).to_u16 | adl
                self.memory[addr] = self.reg_a
                self.cycles_remaining -= 1
            when Instructions::STA_ABS
                self.cycles_remaining = 3
                adl = advance_next_ins()
                adh = advance_next_ins()
                addr = (adh.to_u16 << 8).to_u16 | adl
                self.memory[addr] = self.reg_a
                self.cycles_remaining -= 1
            when Instructions::ADC_IMM
                self.cycles_remaining = 1
                value = advance_next_ins()
                #Check for overflow, if so, set the carry bit to 1
                result = self.reg_a &+ value &+ self.processor_status.to_slice[0]
                self.processor_status[0] = (self.reg_a & 0x80) != (result & 0x80)
                overflow = ~(self.reg_a ^ value) & (self.reg_a ^ result) & 0x80
                self.reg_a = result
                # puts overflow.to_s(16)
                self.processor_status[5] = overflow == 0x80
                self.processor_status[1] = result == 0
                self.processor_status[6] = (result & 0x80) == 0x80
                self.cycles_remaining -= 1

            when Instructions::ADC_ZERO
                self.cycles_remaining = 2
                adl = advance_next_ins()
                addr = (0x00 << 8).to_u16 | adl
                value = self.memory[addr]
                result = self.reg_a &+ value &+ self.processor_status.to_slice[0]
                self.processor_status[0] = (self.reg_a & 0x80) != (result & 0x80)
                overflow = ~(self.reg_a ^ value) & (self.reg_a ^ result) & 0x80
                self.reg_a = result
                # puts overflow.to_s(16)
                self.processor_status[5] = overflow == 0x80
                self.processor_status[1] = result == 0
                self.processor_status[6] = (result & 0x80) == 0x80
                self.cycles_remaining -= 1
            when Instructions::ADC_ABS
                self.cycles_remaining = 3
                adl = advance_next_ins()
                adh = advance_next_ins()
                addr = (adh << 8).to_u16 | adl
                value = self.memory[addr]
                result = self.reg_a &- value &+ self.processor_status.to_slice[0]
                self.processor_status[0] = (self.reg_a & 0x80) != (result & 0x80)
                overflow = ~(self.reg_a ^ value) & (self.reg_a ^ result) & 0x80
                self.reg_a = result
                # puts overflow.to_s(16)
                self.processor_status[5] = overflow == 0x80
                self.processor_status[1] = result == 0
                self.processor_status[6] = (result & 0x80) == 0x80
                self.cycles_remaining -= 1
            when Instructions::ADC_INDIRECT_X
                self.cycles_remaining = 5
                adl = advance_next_ins()
                zaddr = (0x00 << 8).to_u16 | adl
                addr = self.memory[zaddr+self.reg_x]
                self.cycles_remaining -= 2 #2 cycles, one to add the reg_x, and one to get the memory contents
                value = self.memory[addr]
                self.cycles_remaining -= 1
                result = self.reg_a &+ value &+ self.processor_status.to_slice[0]
                self.processor_status[0] = (self.reg_a & 0x80) != (result & 0x80)
                overflow = ~(self.reg_a ^ value) & (self.reg_a ^ result) & 0x80
                self.reg_a = result
                # puts overflow.to_s(16)
                self.processor_status[5] = overflow == 0x80
                self.processor_status[1] = result == 0
                self.processor_status[6] = (result & 0x80) == 0x80
                self.cycles_remaining -= 1
            when Instructions::ADC_Y_INDIRECT
                self.cycles_remaining = 5
                zadl = advance_next_ins()
                zaddr = (0x00 << 8).to_u16 | zadl
                adl = self.memory[zaddr]
                adh = self.memory[zaddr+1]
                addr = (adh.to_u16 << 8).to_u16 | adl
                self.cycles_remaining -= 1 
                value = self.memory[addr+self.reg_y]
                self.cycles_remaining -= 2 #2 cycles, one to add the reg_y, and one to get the memory contents
                result = self.reg_a &+ value &+ self.processor_status.to_slice[0]
                self.processor_status[0] = (self.reg_a & 0x80) != (result & 0x80)
                overflow = ~(self.reg_a ^ value) & (self.reg_a ^ result) & 0x80
                self.reg_a = result
                # puts overflow.to_s(16)
                self.processor_status[5] = overflow == 0x80
                self.processor_status[1] = result == 0
                self.processor_status[6] = (result & 0x80) == 0x80
                self.cycles_remaining -= 1
            when Instructions::SBC_ABS
                self.cycles_remaining = 3
                adh = advance_next_ins()
                adl = advance_next_ins()
                addr = (adh << 8).to_u16 | adl
                value = self.memory[addr]
                result = self.reg_a &- value &+ self.processor_status.to_slice[0]
                self.processor_status[0] = (self.reg_a & 0x80) != (result & 0x80)
                overflow = ~(self.reg_a ^ value) & (self.reg_a ^ result) & 0x80
                self.reg_a = result
                # puts overflow.to_s(16)
                self.processor_status[5] = overflow == 0x80
                self.processor_status[1] = result == 0
                self.processor_status[6] = (result & 0x80) == 0x80
                self.cycles_remaining -= 1
            when Instructions::SBC_ZERO
                self.cycles_remaining = 2
                adl = advance_next_ins()
                addr = (0x00 << 8).to_u16 | adl
                value = self.memory[addr]
                result = self.reg_a &- value &+ self.processor_status.to_slice[0]
                self.processor_status[0] = (self.reg_a & 0x80) != (result & 0x80)
                overflow = ~(self.reg_a ^ value) & (self.reg_a ^ result) & 0x80
                self.reg_a = result
                # puts overflow.to_s(16)
                self.processor_status[5] = overflow == 0x80
                self.processor_status[1] = result == 0
                self.processor_status[6] = (result & 0x80) == 0x80
                self.cycles_remaining -= 1
            when Instructions::SBC_IMM
                self.cycles_remaining = 2
                value = advance_next_ins()
                #Check for underflow, if so, set the carry bit to 1
                result = self.reg_a &- value &+ self.processor_status.to_slice[0]
                self.processor_status[0] = (self.reg_a & 0x80) != (result & 0x80)
                overflow = ~(self.reg_a ^ value) & (self.reg_a ^ result) & 0x80
                self.reg_a = result
                # puts overflow.to_s(16)
                self.processor_status[5] = overflow == 0x80
                self.processor_status[1] = result == 0
                self.processor_status[6] = (result & 0x80) == 0x80
                self.cycles_remaining -= 1
            when Instructions::SBC_INDIRECT_X
                self.cycles_remaining = 5
                adl = advance_next_ins()
                zaddr = (0x00 << 8).to_u16 | adl
                addr = self.memory[zaddr+self.reg_x]
                self.cycles_remaining -= 2
                value = self.memory[addr]
                self.cycles_remaining -= 1
                #Check for underflow, if so, set the carry bit to 1
                result = self.reg_a &- value &+ self.processor_status.to_slice[0]
                self.processor_status[0] = (self.reg_a & 0x80) != (result & 0x80)
                overflow = ~(self.reg_a ^ value) & (self.reg_a ^ result) & 0x80
                self.reg_a = result
                # puts overflow.to_s(16)
                self.processor_status[5] = overflow == 0x80
                self.processor_status[1] = result == 0
                self.processor_status[6] = (result & 0x80) == 0x80
                self.cycles_remaining -= 1
            when Instructions::SBC_Y_INDIRECT
                self.cycles_remaining = 5
                adl = advance_next_ins()
                zaddr = (0x00 << 8).to_u16 | adl
                addr = self.memory[zaddr]
                self.cycles_remaining -= 1
                value = self.memory[addr+self.reg_y]
                self.cycles_remaining -= 2
                #Check for underflow, if so, set the carry bit to 1
                result = self.reg_a &- value &+ self.processor_status.to_slice[0]
                self.processor_status[0] = (self.reg_a & 0x80) != (result & 0x80)
                overflow = ~(self.reg_a ^ value) & (self.reg_a ^ result) & 0x80
                self.reg_a = result
                # puts overflow.to_s(16)
                self.processor_status[5] = overflow == 0x80
                self.processor_status[1] = result == 0
                self.processor_status[6] = (result & 0x80) == 0x80
                self.cycles_remaining -= 1
            when Instructions::SEC
                self.cycles_remaining = 1
                self.processor_status[0] = true
            when Instructions::CLC
                self.cycles_remaining = 1
                self.processor_status[0] = false
            else
                puts "Failed to decode instruction: #{ins.to_s(16)} @ #{self.program_counter.to_s(16)}"
                return
            end
            ins = next_ins()
        end
    end

    #Loads a program into memory at address 0x0200
    def load_program(program : Array(UInt8))
        program.each_with_index do |b, index|
            self.memory[0x0200 + index] = b
        end
    end

    def get_processor_status_string
        String.build do |str|
            if self.processor_status[0] == true
                str << 1
            else
                str << 0
            end
            if self.processor_status[1] == true
                str << 1
            else
                str << 0
            end
            if self.processor_status[2] == true
                str << 1
            else
                str << 0
            end
            if self.processor_status[3] == true
                str << 1
            else
                str << 0
            end
            if self.processor_status[4] == true
                str << 1
            else
                str << 0
            end
            if self.processor_status[5] == true
                str << 1
            else
                str << 0
            end
            if self.processor_status[6] == true
                str << 1
            else
                str << 0
            end
        end
    end
end

struct Memory
    #The actual stored data
    #   The first page ($0000 - $00FF) is called the zero page
    #   The second page ($0100 - $01FF) is reserved for the system stack and cannot be relocated
    #   The last 6 bytes are reserved for the following
    #       $FFFA-$FFFB : non-maskable interrupt handler
    #       $FFFC-$FFFD : power reset handler
    #       $FFFE-$FFFF : BRK/interrupt request handler
    #   Any other locations are free to use by the user
    # getter data = StaticArray(UInt8, 65536).new(0)
    getter data = Bytes.new(65536, 0)

    #Read at a 16-bit address
    def [](index : UInt16)
        self.data[index]
    end

    #Read at an 8-bit address
    def [](index : UInt8)
        self.data[index]
    end

    #Use a 32-bit address to store an 8-bit value
    def []=(index : Int32, value : UInt8)
        self.data[index] = value
    end

    #Use a 16-bit address to store an 8-bit value
    def []=(index : UInt16, value : UInt8)
        self.data[index] = value
    end

    #Use an 8-bit address to store an 8-bit value
    def []=(index : UInt8, value : UInt8)
        self.data[index] = value
    end

    def [](range : Range)
        self.data[range]
    end
end

enum Instructions : UInt8
    #This instruction will load an immediate byte into the X register.
    #
    #This instruction is 2 cycles and 2 bytes and operate as follows:
    #```
    #Cycle 1: Fetch Opcode
    #Cycle 2: Read byte and load into X
    #```
    LDX_IMM = 0xA2
    #This instruction will load a byte into the X register given a higher byte of a zero page address
    #
    #This instruction is 3 cycles and 2 bytes
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read higher byte from program
    #Cycle 3    Load from zero page address into X
    #```
    LDX_ZERO = 0xA5
    #This instruction will load a byte from a given 16-bit memory address into the X register.
    #
    #This instruction is 4 cycles and 3 bytes and operate as follows:
    #```
    #Cycle 1: Fetch Opcode
    #Cycle 2: Read ADL
    #Cycle 3: Read ADH
    #Cycle 4: Load 8-bit data of address 0x{ADL}{ADH} into X
    #```
    LDX_ABS = 0xAE
    #This instruction will load a byte from a given 16-bit memory address, indexed to Y
    #
    #This instruction is 4 cycles, 3 bytes and operates as follows:
    #```
    #Cycle 1: Fetch Opcode
    #Cycle 2: Read ADL
    #Cycle 3: Read ADH
    #Cycle 4: Load 8-biot data of address 0x{ADL}{ADH}+Y
    #```
    #
    #X and Y registers are known as index registers. They are used to offset an address, such as indexing into an array.
    #Example:
    #```
    #arr = ['a', 'b', 'c']
    #arr[1] #'b'
    #```
    #The indexing is easily done with the X and Y registers
    #```
    #ldx #1
    #lda $5000, X ;Assuming that the array starts at address 0x5000, we index into 0x5001 using X
    #```
    #
    LDX_ABS_Y = 0xBE
    #This instruction will load a byte from a given 16-bit memory address, indexed to Y
    #
    #This instruction is 4 cycles, 2 bytes and operates as follows:
    #```
    #Cycle 1: Fetch Opcode
    #Cycle 2: Read ADH
    #Cycle 3: Load 8-bit data of address 0x00{ADH}+Y
    #```
    #
    #X and Y registers are known as index registers. They are used to offset an address, such as indexing into an array.
    #Example:
    #```
    #arr = ['a', 'b', 'c']
    #arr[1] #'b'
    #```
    #The indexing is easily done with the X and Y registers
    #```
    #ldx #1
    #lda $50, X ;Assuming that the array starts at address 0x50, we index into 0x51 using X
    #```
    #
    LDX_ZERO_Y = 0xB6
    #This instruction will store the value in register X in an address in the zero page
    #
    #This takes two bytes and three cycles
    #
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read ADH
    #Cycle 3    Store contents of X at 0x00{ADH} where ADH is the address within the zero page, and 0x00 is the lower byte of the address
    #```
    STX_ZERO = 0x86
    #This instruction will store the value in register X in an address in the zero page
    #
    #This takes two bytes and three cycles
    #
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read ADH
    #Cycle 3    Store contents of X at 0x00{ADH} where ADH is the address within the zero page, and 0x00 is the lower byte of the address
    #```
    STX_ZERO_Y = 0x86
    #This instruction will store the value in register X in an absolute address
    #
    #This takes three bytes and 4 cycles to complete
    #
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read ADL
    #Cycle 3    Read ADH
    #Cycle 4    Store contents of X at 0x{ADL}{ADH}
    #```
    STX_ABS = 0x8E
    #This instruction will store the value in register Y in an address in the zero page
    #
    #This takes two bytes and three cycles
    #
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read ADH
    #Cycle 3    Store contents of Y at 0x00{ADH} where ADH is the address within the zero page, and 0x00 is the lower byte of the address
    #```
    STY_ZERO = 0x84
    #This instruction will store the value in register Y in an address in the zero page indexed to X
    #
    #This takes two bytes and four cycles
    #
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read ADH
    #Cycle 3    
    #Cycle 4    Store contents of Y at 0x00{ADH}+X where ADH is the address within the zero page, and 0x00 is the lower byte of the address and X is the contents of X register
    #```
    STY_ZERO_X = 0x94
    #This instruction will store the value in register Y in an absolute address
    #
    #This takes three bytes and 4 cycles to complete
    #
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read ADL
    #Cycle 3    Read ADH
    #Cycle 4    Store contents of Y at 0x{ADL}{ADH}
    #```
    STY_ABS = 0x8C
    #This instruction will load a byte into the Y register.
    #
    #This instruction is 2 cycles and 2 bytes and operate as follows:
    #```
    #Cycle 1: Fetch Opcode
    #Cycle 2: Read byte and load into Y
    #```
    LDY_IMM = 0xA0
    #This instruction will load a byte into the Y register given a higher byte of a zero page address
    #
    #This instruction is 3 cycles and 2 bytes
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read higher byte from program
    #Cycle 3    Load from zero page address into Y
    #```
    LDY_ZERO = 0xA4
    #This instruction will load a byte into the Y register given a higher byte of a zero page address
    #
    #This instruction is 4 cycles and 2 bytes
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    ADH = Read higher byte from program
    #Cycle 3    Addr = 0x00{ADH} + X
    #Cycle 4    Load contents of Addr into Y
    #```
    LDY_ZERO_X = 0xB4
    #This instruction will load a byte from a given 16-bit memory address into the Y register.
    #
    #This instruction is 4 cycles and 3 bytes and operate as follows:
    #```
    #Cycle 1: Fetch Opcode
    #Cycle 2: Read ADL
    #Cycle 3: Read ADH
    #Cycle 4: Increment address by X
    #Cycle 4: Load 8-bit data of address 0x{ADL}{ADH}+X into Y
    #```
    LDY_ABS_X = 0xBC
    #This instruction will load a byte from a given 16-bit memory address into the Y register.
    #
    #This instruction is 4 cycles and 3 bytes and operate as follows:
    #```
    #Cycle 1: Fetch Opcode
    #Cycle 2: Read ADL
    #Cycle 3: Read ADH
    #Cycle 4: Load 8-bit data of address 0x{ADL}{ADH} into Y
    #```
    LDY_ABS = 0xAC
    #This instruction will load a byte into the A register.
    #
    #This instruction is 2 cycles and 2 bytes and operate as follows:
    #```
    #Cycle 1: Fetch Opcode
    #Cycle 2: Read byte and load into A
    #```
    LDA_IMM = 0xA9
    #This instruction will load a byte into the A register given a higher byte of a zero page address
    #
    #This instruction is 3 cycles and 2 bytes
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read higher byte from program
    #Cycle 3    Load from zero page address into accumulator
    #```
    LDA_ZERO = 0xA5
    #This instruction will load a byte from an absolute address into the accumulator
    #
    #This instruction is 4 cycles and 3 bytes
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read lower byte
    #Cycle 3    Read higher byte
    #Cycle 4    Load byte from given address into accumulator
    #```
    LDA_ABS = 0xAD
    #This instruction will store the value in the accumulator (register A) in an address in the zero page
    #
    #This takes two bytes and three cycles
    #
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read ADH
    #Cycle 3    Store contents of A at 0x00{ADH} where ADH is the address within the zero page, and 0x00 is the lower byte of the address
    #```
    STA_ZERO = 0x85
    #This instruction will store the contents of the accumulator into an absolute address
    #
    #This instruction is 4 cycles and 3 bytes
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read lower byte
    #Cycle 3    Read higher byte
    #Cycle 4    Store contents of accumulator into given address
    #```
    STA_ABS = 0x8D
    #This instruction will add an immediate value into the accumulator (A register) with a carry bit. If the operation overflows beyond 255, then the result with a carry bit of 1 means to interpret the results as 255 + A.
    #
    #This instruction takes two bytes and takes three cycles to complete.
    #
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read byte from program
    #Cycle 3    Add read byte to A, set carry bit if necessary
    #```
    ADC_IMM = 0x69
    #This instruction will add the contents of an address in the zero page to the accumulator.
    #
    #This instruction takes 3 bytes and takes 4 cycles to complete.
    #
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 3    Read ADH
    #Cycle 4    Add contents of 0x00{ADH} to register A
    #```
    ADC_ZERO = 0x65
    #This instruction will add the contents of an absolute memory location into the accumulator (A register) with a carry bit. 
    #
    #If the operation overflows beyond 255, then the result with a carry bit of 1 means to interpret the results as 255 + A.
    #
    #This instruction takes 3 bytes and takes 4 cycles to complete.
    #
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read ADL
    #Cycle 3    Read ADH
    #Cycle 4    Add contents of 0x{ADL}{ADH} to register A
    #```
    ADC_ABS = 0x6D
    #This instruction will add the contents of an indirect memory location, from the zero page given by the instruction's opcode with X added, into the accumulator (A register) with a carry bit. 
    #
    #If the operation overflows beyond 255, then the result with a carry bit of 1 means to interpret the results as 255 + A.
    #
    #This instruction takes 2 bytes and takes 6 cycles to complete.
    #
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read ADH
    #Cycle 3    ADDR = 0x00{ADH}+X
    #Cycle 4    Get ADL from ADDR
    #Cycle 5    Get ADH from ADDR
    #Cycle 6    Add contents of 0x{ADL}{ADH} to register A
    #```
    ADC_INDIRECT_X = 0x61
    #This instruction will add the contents of an indirect memory location, from the zero page given by the instruction's opcode, followed by Y being added to it, into the accumulator (A register) with a carry bit. 
    #
    #This will take a zero page address for loading an absolute address, indexed to Y
    #
    #If the operation overflows beyond 255, then the result with a carry bit of 1 means to interpret the results as 255 + A.
    #
    #This instruction takes 2 bytes and takes 6 cycles to complete.
    #
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read ADH, ADDR = 0x00{ADH}
    #Cycle 3    Get ADL from ADDR
    #Cycle 4    Get ADH from ADDR
    #Cycle 5    ADDR = 0x{ADL}{ADH}+Y
    #Cycle 6    Add contents of ADDR to register A
    #```
    ADC_Y_INDIRECT = 0x71
    #This instruction will subtract an immediate value from the accumulator (A register) with a carry bit. 
    #
    #If the operation underflows below 0, then the result with a carry bit of 1 means to interpret the results as 255 - A.
    #
    #This instruction takes two bytes and takes three cycles to complete.
    #
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read byte from program
    #Cycle 3    Sub read byte from A, set carry bit if necessary
    #```
    SBC_IMM = 0xE9
    #This instruction will subtract the contents of an address in the zero page from the accumulator. 
    #
    #If the operation underflows below 0, then the result with a carry bit of 1 means to interpret the results as 255 - A.
    #
    #This instruction takes 3 bytes and takes 4 cycles to complete.
    #
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 3    Read ADH
    #Cycle 4    Subtract contents of 0x00{ADH} to register A
    #```
    SBC_ZERO = 0xE5
    #This instruction will add the contents of an absolute memory location into the accumulator (A register) with a carry bit. 
    #
    #If the operation overflows beyond 255, then the result with a carry bit of 1 means to interpret the results as 255 + A.
    #
    #This instruction takes 3 bytes and takes 4 cycles to complete.
    #
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read ADL
    #Cycle 3    Read ADH
    #Cycle 4    Subtract contents of 0x{ADL}{ADH} to register A
    #```
    SBC_ABS = 0xED
    SBC_INDIRECT_X = 0xE1
    SBC_Y_INDIRECT = 0xF1
    #This will read a word from the program and push the current program counter onto the stack then setting the program counter to the acquired word.
    #
    #This instruction is 7 cycles and 3 bytes
    #
    #Normally in the hardware, the lower byte read is called ADL
    #and the higher byte read is called ADH
    #In the hardware, we also have PCH (program counter high) and PCL (program counter low)
    #The hardware will spend two cycles to set the ADL->PCL and ADH->PCH
    #
    #   Vocabulary:
    #       ADL : Target Address Low
    #       ADH : Target Address high
    #       PCL : Program Counter low
    #       PCH : Program Counter high
    #       AD  : Target Address
    #       PC  : Program Counter
    #
    #So the hardware is really like this:
    #```
    #   Cycle 1    Fetch Opcode
    #   Cycle 2    Read ADL
    #   Cycle 3    Push PCH
    #   Cycle 4    Push PCL
    #   Cycle 5    Fetch ADH
    #   Cycle 6    ADL->PCL
    #   Cycle 7    ADH->PCH
    #```
    #
    #Source: http://archive.6502.org/datasheets/synertek_programming_manual.pdf p118
    #
    #Our cycles are like this:
    #
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Read ADL
    #Cycle 3    Read ADH
    #Cycle 4    AD = ADH | ADL
    #Cycle 5    Push PCH
    #Cycle 6    Push PCL
    #Cycle 7    AD->PC
    #```
    JSR     = 0x20
    #This will return from a subroutine by popping a word off the stack and setting the program counter to it + 1
    #
    #This instruction is 6 cycles and 1 byte.
    #```
    #Cycle 1    Fetch Opcode
    #Cycle 2    Pop ADL
    #Cycle 3    Pop ADH
    #Cycle 4    AD = ADH | ADL
    #Cycle 5    AD->PC
    #Cycle 6    PC->PC+1
    #```
    RTS     = 0x60
    #This instruction will set the carry flag to 1
    SEC     = 0x38
    #This instruction will clear the carry flag to 0
    CLC     = 0x18
end

file_path = ""
parser = OptionParser.parse do |parser|
    parser.on("-f FILE", "The file of the program to run in 6502 instructions") do |value|
        file_path = value
    end
    parser.on("-h", "Print the usage") do
        puts parser
        exit
    end
end
if file_path == ""
    puts "Expected a program to run, got nothing. Please use -h for more info."
end
program = Bytes.new(64)
File.open(file_path, "rb") do |file|
    file.each_byte.with_index do |byte, index|
        program[index] = byte
    end
end
require "io/hexdump"
puts program.hexdump
cpu = CPU.new
cpu.load_program(program.to_a)
cpu.execute
puts "ar        #{cpu.reg_a.to_s(16)}"
puts "xr        #{cpu.reg_x.to_s(16)}"
puts "yr        #{cpu.reg_y.to_s(16)}"
puts "pc        #{cpu.program_counter.to_s(16)}"
puts "sp        #{cpu.stack_pointer.to_s(16)}"
puts "czidbvn   #{cpu.get_processor_status_string}"
critical_region = cpu.memory[0x3f56_u16..0x3f5e]
puts critical_region.hexdump
zero_page = cpu.memory[0..8]
puts zero_page.hexdump