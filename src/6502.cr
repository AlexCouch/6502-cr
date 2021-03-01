require "bit_array"

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
        lower_byte = ((value & 0xFF00) >> 8).to_u8
        self.stack_push(lower_byte)
        higher_byte = (value & 0x00FF).to_u8
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
        next_ins = next_ins()
        until next_ins == 0
            case Instructions.new(next_ins)
            when Instructions::LDX_IMM
                
                self.cycles_remaining = 1
                value = advance_next_ins()
                self.reg_x = value
            when Instructions::LDY_IMM
                
                self.cycles_remaining = 1
                value = advance_next_ins()
                self.reg_y = value

            when Instructions::JSR
                
                self.cycles_remaining = 6
                lower_byte = advance_next_ins()
                higher_byte = (advance_next_ins().to_u16 << 8).to_u16
                jump_target = (higher_byte | lower_byte).to_u16
                self.stack_push(self.program_counter)
                self.program_counter = jump_target - 1
                self.cycles_remaining -= 2
            when Instructions::RTS
                
                self.cycles_remaining = 5
                lower_byte = (self.stack_pop.to_u16).to_u16
                higher_byte = (self.stack_pop.to_u16 << 8).to_u16
                jump_target = (higher_byte | lower_byte).to_u16
                self.cycles_remaining -= 1
                self.program_counter = jump_target + 1
                self.cycles_remaining -= 2  #We decrement by two because we decrementing the jump target by 1 and that is two cycles
            else
                puts "Failed to decode instruction: #{next_ins} @ #{self.program_counter}"
                return
            end
            next_ins = next_ins()
        end
    end

    #Loads a program into memory at address 0x0200
    def load_program(program : Array(UInt8))
        program.each_with_index do |b, index|
            self.memory[index] = b
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
    getter data = Array(UInt8).new(65536, 0)

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
end

enum Instructions : UInt8
    #This instruction will load a byte into the X register.
    #
    #This instruction is 2 cycles and 2 bytes and operate as follows:
    #```
    #Cycle 1: Fetch Opcode
    #Cycle 2: Read byte and load into X
    #```
    LDX_IMM = 0xA2
    #This instruction will load a byte into the Y register.
    #
    #This instruction is 2 cycles and 2 bytes and operate as follows:
    #```
    #Cycle 1: Fetch Opcode
    #Cycle 2: Read byte and load into Y
    #```
    LDY_IMM = 0xA0
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
end

cpu = CPU.new
program = Array(UInt8).new(64, 0)
program[0] = Instructions::LDY_IMM.value
program[1] = 0x05_u8
program[2] = Instructions::JSR.value
program[3] = 0x21_u8
program[4] = 0x02_u8
program[32] = Instructions::RTS.value
cpu.load_program(program)
cpu.execute
puts cpu.reg_x
puts cpu.reg_y
puts cpu.program_counter
puts cpu.cycles_remaining