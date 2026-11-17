// ============================================================================
// SYSTEMVERILOG HDL: SYNTHESIZABLE SoC RTL + OOP TESTBENCH
// File Name: smart_home_soc_top_tb.sv
// ============================================================================
`timescale 1ns / 1ps

// ============================================================================
// PART 1: SYNTHESIZABLE CORE VLSI MODULES & TOP INTEGRATION
// ============================================================================

// ----------------------------------------------------------------------------
// 1. Autonomous Thermal Intelligence Block
// ----------------------------------------------------------------------------
module thermal_intelligence_block #(
    parameter width_p          = 8,
    parameter default_thresh_p = 8'd35,
    parameter hysteresis_p     = 8'd3
)(
    input  logic               clk_i,
    input  logic               rst_n_i,
    input  logic [width_p-1:0] temp_data_i,
    input  logic [width_p-1:0] thresh_reg_i,
    output logic               cooling_en_o,
    output logic               overheat_alarm_o
);

    logic [width_p-1:0] active_thresh;
    assign active_thresh = (thresh_reg_i == '0) ? default_thresh_p : thresh_reg_i;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            cooling_en_o     <= 1'b0;
            overheat_alarm_o <= 1'b0;
        end else begin
            if (temp_data_i >= active_thresh) begin
                cooling_en_o     <= 1'b1;
                overheat_alarm_o <= 1'b1;
            end else if (temp_data_i < (active_thresh - hysteresis_p)) begin
                cooling_en_o     <= 1'b0;
                overheat_alarm_o <= 1'b0;
            end
        end
    end

endmodule

// ----------------------------------------------------------------------------
// 2. Digital Luminance Processing Module
// ----------------------------------------------------------------------------
module digital_luminance_processor #(
    parameter width_p       = 8,
    parameter lpf_shift_p   = 2,
    parameter dark_thresh_p = 8'd50
)(
    input  logic               clk_i,
    input  logic               rst_n_i,
    input  logic [width_p-1:0] ambient_light_i,
    output logic               lighting_en_o
);

    logic [width_p+lpf_shift_p-1:0] filter_acc;
    logic [width_p-1:0]             filtered_light;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            filter_acc     <= '0;
            filtered_light <= '0;
        end else begin
            filter_acc     <= filter_acc - (filter_acc >> lpf_shift_p) + ambient_light_i;
            filtered_light <= filter_acc >> lpf_shift_p;
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            lighting_en_o <= 1'b0;
        end else begin
            if (filtered_light < dark_thresh_p)
                lighting_en_o <= 1'b1;
            else
                lighting_en_o <= 1'b0;
        end
    end

endmodule

// ----------------------------------------------------------------------------
// 3. FSM-Driven Security & Intrusion Shield
// ----------------------------------------------------------------------------
module security_intrusion_shield #(
    parameter clk_freq_hz_p = 50_000_000
)(
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic arm_cmd_i,
    input  logic disarm_cmd_i,
    input  logic motion_sensor_i,
    output logic led_strobe_o,
    output logic alarm_1khz_o
);

    typedef enum logic [1:0] {
        ST_NORMAL = 2'b00,
        ST_ARMED  = 2'b01,
        ST_ALARM  = 2'b10
    } state_e;

    state_e current_state, next_state;

    logic motion_d, motion_pulse;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) motion_d <= 1'b0;
        else          motion_d <= motion_sensor_i;
    end
    assign motion_pulse = motion_sensor_i && !motion_d;

    localparam div_count_1khz = (clk_freq_hz_p / (2 * 1000)) - 1;
    logic [31:0] cnt_1khz;
    logic        clk_1khz;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            cnt_1khz <= '0;
            clk_1khz <= 1'b0;
        end else if (cnt_1khz >= div_count_1khz) begin
            cnt_1khz <= '0;
            clk_1khz <= ~clk_1khz;
        end else begin
            cnt_1khz <= cnt_1khz + 1'b1;
        end
    end

    localparam div_count_strobe = (clk_freq_hz_p / (2 * 10)) - 1;
    logic [31:0] cnt_strobe;
    logic        strobe_clk;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            cnt_strobe <= '0;
            strobe_clk <= 1'b0;
        end else if (cnt_strobe >= div_count_strobe) begin
            cnt_strobe <= '0;
            strobe_clk <= ~strobe_clk;
        end else begin
            cnt_strobe <= cnt_strobe + 1'b1;
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) current_state <= ST_NORMAL;
        else          current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        case (current_state)
            ST_NORMAL: begin
                if (arm_cmd_i) next_state = ST_ARMED;
            end
            ST_ARMED: begin
                if (disarm_cmd_i)       next_state = ST_NORMAL;
                else if (motion_pulse)  next_state = ST_ALARM;
            end
            ST_ALARM: begin
                if (disarm_cmd_i)       next_state = ST_NORMAL;
            end
            default: next_state = ST_NORMAL;
        endcase
    end

    assign led_strobe_o = (current_state == ST_ALARM) ? strobe_clk : 1'b0;
    assign alarm_1khz_o = (current_state == ST_ALARM) ? clk_1khz   : 1'b0;

endmodule

// ----------------------------------------------------------------------------
// 4. Automated Access & Gate Control Logic
// ----------------------------------------------------------------------------
module access_gate_control #(
    parameter clk_freq_hz_p    = 50_000_000,
    parameter auto_close_sec_p = 5
)(
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic doorbell_pulse_i,
    output logic gate_pwm_o,
    output logic gate_open_status_o
);

    localparam cnt_20ms         = clk_freq_hz_p / 50;
    localparam pwm_close_ticks  = (clk_freq_hz_p / 1000) * 1;
    localparam pwm_open_ticks   = (clk_freq_hz_p / 1000) * 2;
    localparam auto_close_ticks = clk_freq_hz_p * auto_close_sec_p;

    logic [31:0] pwm_counter;
    logic [31:0] auto_close_counter;
    logic        gate_open;

    logic doorbell_d, doorbell_edge;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) doorbell_d <= 1'b0;
        else          doorbell_d <= doorbell_pulse_i;
    end
    assign doorbell_edge = doorbell_pulse_i && !doorbell_d;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            gate_open          <= 1'b0;
            auto_close_counter <= '0;
        end else begin
            if (doorbell_edge) begin
                gate_open          <= 1'b1;
                auto_close_counter <= '0;
            end else if (gate_open) begin
                if (auto_close_counter >= auto_close_ticks) begin
                    gate_open          <= 1'b0;
                    auto_close_counter <= '0;
                end else begin
                    auto_close_counter <= auto_close_counter + 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pwm_counter <= '0;
            gate_pwm_o  <= 1'b0;
        end else begin
            if (pwm_counter >= cnt_20ms - 1)
                pwm_counter <= '0;
            else
                pwm_counter <= pwm_counter + 1'b1;

            if (gate_open)
                gate_pwm_o <= (pwm_counter < pwm_open_ticks);
            else
                gate_pwm_o <= (pwm_counter < pwm_close_ticks);
        end
    end

    assign gate_open_status_o = gate_open;

endmodule

// ----------------------------------------------------------------------------
// 5. Global State & Security Governance Register
// ----------------------------------------------------------------------------
module global_governance_register (
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic [1:0] mode_select_i,
    input  logic [7:0] temp_thresh_in_i,
    output logic [1:0] sys_mode_o,
    output logic [7:0] active_temp_thresh_o,
    output logic       high_sens_override_o
);

    typedef enum logic [1:0] {
        MODE_COMFORT  = 2'b00,
        MODE_LOCKDOWN = 2'b01
    } mode_e;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            sys_mode_o           <= MODE_COMFORT;
            active_temp_thresh_o <= 8'd35;
            high_sens_override_o <= 1'b0;
        end else begin
            sys_mode_o <= mode_select_i;
            
            case (mode_select_i)
                MODE_COMFORT: begin
                    active_temp_thresh_o <= temp_thresh_in_i;
                    high_sens_override_o <= 1'b0;
                end
                MODE_LOCKDOWN: begin
                    active_temp_thresh_o <= 8'd30;
                    high_sens_override_o <= 1'b1;
                end
                default: begin
                    sys_mode_o           <= MODE_COMFORT;
                    active_temp_thresh_o <= temp_thresh_in_i;
                    high_sens_override_o <= 1'b0;
                end
            endcase
        end
    end

endmodule

// ----------------------------------------------------------------------------
// 6. Core RTL Integration Engine (Top-Level Smart Home SoC)
// ----------------------------------------------------------------------------
module smart_home_soc #(
    parameter clk_freq_hz_p = 50_000_000,
    parameter data_width_p  = 8
)(
    input  logic                    clk_i,
    input  logic                    rst_n_i,

    // Environmental Sensors
    input  logic [data_width_p-1:0] temp_sensor_i,
    input  logic [data_width_p-1:0] light_sensor_i,
    
    // User Configuration & Controls
    input  logic [1:0]              sys_mode_select_i,
    input  logic [data_width_p-1:0] user_temp_thresh_i,
    input  logic                    arm_system_i,
    input  logic                    disarm_system_i,
    input  logic                    motion_sensor_i,
    input  logic                    doorbell_i,

    // Hardware Actuators & Status Outputs
    output logic                    cooling_actuator_o,
    output logic                    overheat_buzzer_o,
    output logic                    smart_lighting_o,
    output logic                    strobe_led_o,
    output logic                    auditory_alarm_o,
    output logic                    servo_gate_pwm_o,
    output logic                    gate_status_led_o,
    output logic [1:0]              current_sys_mode_o
);

    // Internal Signal Interconnect Networks
    logic [1:0]              sys_mode_net;
    logic [data_width_p-1:0] active_thresh_net;
    logic                    high_sens_net;
    logic                    effective_motion_net;

    global_governance_register u_governance (
        .clk_i                (clk_i),
        .rst_n_i              (rst_n_i),
        .mode_select_i        (sys_mode_select_i),
        .temp_thresh_in_i     (user_temp_thresh_i),
        .sys_mode_o           (sys_mode_net),
        .active_temp_thresh_o (active_thresh_net),
        .high_sens_override_o (high_sens_net)
    );

    assign current_sys_mode_o = sys_mode_net;

    thermal_intelligence_block #(
        .width_p(data_width_p)
    ) u_thermal (
        .clk_i           (clk_i),
        .rst_n_i         (rst_n_i),
        .temp_data_i     (temp_sensor_i),
        .thresh_reg_i    (active_thresh_net),
        .cooling_en_o    (cooling_actuator_o),
        .overheat_alarm_o(overheat_buzzer_o)
    );

    digital_luminance_processor #(
        .width_p(data_width_p)
    ) u_luminance (
        .clk_i          (clk_i),
        .rst_n_i        (rst_n_i),
        .ambient_light_i(light_sensor_i),
        .lighting_en_o  (smart_lighting_o)
    );

    assign effective_motion_net = high_sens_net ? (motion_sensor_i || doorbell_i) : motion_sensor_i;

    security_intrusion_shield #(
        .clk_freq_hz_p(clk_freq_hz_p)
    ) u_security (
        .clk_i          (clk_i),
        .rst_n_i        (rst_n_i),
        .arm_cmd_i      (arm_system_i || high_sens_net),
        .disarm_cmd_i   (disarm_system_i),
        .motion_sensor_i(effective_motion_net),
        .led_strobe_o   (strobe_led_o),
        .alarm_1khz_o   (auditory_alarm_o)
    );

    access_gate_control #(
        .clk_freq_hz_p(clk_freq_hz_p)
    ) u_gate (
        .clk_i             (clk_i),
        .rst_n_i           (rst_n_i),
        .doorbell_pulse_i  (doorbell_i),
        .gate_pwm_o        (servo_gate_pwm_o),
        .gate_open_status_o(gate_status_led_o)
    );

endmodule


// ============================================================================
// PART 2: OBJECT-ORIENTED SYSTEMVERILOG (OOP) VERIFICATION ENVIRONMENT
// ============================================================================

// ----------------------------------------------------------------------------
// SoC Interface (Connects RTL Module Pins to Verification Objects)
// ----------------------------------------------------------------------------
interface soc_if (input logic clk, input logic rst_n);
    logic [7:0] temp_sensor;
    logic [7:0] light_sensor;
    logic [1:0] sys_mode_select;
    logic [7:0] user_temp_thresh;
    logic       arm_system;
    logic       disarm_system;
    logic       motion_sensor;
    logic       doorbell;

    logic       cooling_actuator;
    logic       overheat_buzzer;
    logic       smart_lighting;
    logic       strobe_led;
    logic       auditory_alarm;
    logic       servo_gate_pwm;
    logic       gate_status_led;
    logic [1:0] current_sys_mode;
endinterface

// ----------------------------------------------------------------------------
// OOP Class 1: Encapsulated Transaction Container
// ----------------------------------------------------------------------------
class Transaction;
    rand logic [7:0] temp_sensor;
    rand logic [7:0] light_sensor;
    rand logic [1:0] sys_mode_select;
    rand logic [7:0] user_temp_thresh;
    rand logic       arm_system;
    rand logic       disarm_system;
    rand logic       motion_sensor;
    rand logic       doorbell;

    function new();
        this.temp_sensor      = 8'd25;
        this.light_sensor     = 8'd100;
        this.sys_mode_select  = 2'b00;
        this.user_temp_thresh = 8'd35;
        this.arm_system       = 1'b0;
        this.disarm_system    = 1'b0;
        this.motion_sensor    = 1'b0;
        this.doorbell         = 1'b0;
    endfunction

    function void print(string prefix = "TX");
        $display("[%s] Temp=%0d C, Light=%0d, Mode=%0b, Motion=%0b, Doorbell=%0b",
                 prefix, temp_sensor, light_sensor, sys_mode_select, motion_sensor, doorbell);
    endfunction
endclass

// ----------------------------------------------------------------------------
// OOP Class 2: Abstract Base Driver & Polymorphic SoC Driver
// ----------------------------------------------------------------------------
virtual class BaseDriver;
    virtual soc_if vif;

    function new(virtual soc_if vif);
        this.vif = vif;
    endfunction

    pure virtual task drive(Transaction tr);
endclass

class SoCDriver extends BaseDriver;
    function new(virtual soc_if vif);
        super.new(vif);
    endfunction

    virtual task drive(Transaction tr);
        @(posedge vif.clk);
        vif.temp_sensor      <= tr.temp_sensor;
        vif.light_sensor     <= tr.light_sensor;
        vif.sys_mode_select  <= tr.sys_mode_select;
        vif.user_temp_thresh <= tr.user_temp_thresh;
        vif.arm_system       <= tr.arm_system;
        vif.disarm_system    <= tr.disarm_system;
        vif.motion_sensor    <= tr.motion_sensor;
        vif.doorbell         <= tr.doorbell;
    endtask
endclass

// ----------------------------------------------------------------------------
// OOP Class 3: Scoreboard Functional Verification Checker
// ----------------------------------------------------------------------------
class Scoreboard;
    virtual soc_if vif;

    function new(virtual soc_if vif);
        this.vif = vif;
    endfunction

    task check_thermal_and_mode();
        @(posedge vif.clk);
        if (vif.temp_sensor >= vif.user_temp_thresh) begin
            if (vif.cooling_actuator && vif.overheat_buzzer)
                $display("[SCOREBOARD PASS] Thermal alarm triggered correctly at %0d C", vif.temp_sensor);
            else
                $error("[SCOREBOARD FAIL] Thermal output response error!");
        end

        if (vif.sys_mode_select == 2'b01 && vif.current_sys_mode == 2'b01) begin
            $display("[SCOREBOARD PASS] System mode successfully updated to Lockdown Mode.");
        end
    endtask
endclass

// ----------------------------------------------------------------------------
// OOP Class 4: Test Environment Component Object
// ----------------------------------------------------------------------------
class Environment;
    SoCDriver      drv;
    Scoreboard     scb;
    virtual soc_if vif;

    function new(virtual soc_if vif);
        this.vif = vif;
        this.drv = new(vif);
        this.scb = new(vif);
    endfunction

    task run_all_tests();
        Transaction tr;

        $display("\n==================================================");
        $display("     EXECUTING OOP SYSTEMVERILOG TESTBENCH SUITE ");
        $display("==================================================");

        // Test 1: Normal Comfort Mode Operation
        tr = new();
        tr.temp_sensor  = 8'd28;
        tr.light_sensor = 8'd120;
        tr.print("TEST 1 - COMFORT");
        drv.drive(tr);
        #100;

        // Test 2: Overheat Thermal Trigger
        tr = new();
        tr.temp_sensor      = 8'd38;
        tr.user_temp_thresh = 8'd35;
        tr.print("TEST 2 - OVERHEAT");
        drv.drive(tr);
        #100;
        scb.check_thermal_and_mode();

        // Test 3: Governance Lockdown Mode
        tr = new();
        tr.sys_mode_select = 2'b01;
        tr.print("TEST 3 - LOCKDOWN");
        drv.drive(tr);
        #100;
        scb.check_thermal_and_mode();

        // Test 4: Intrusion Motion Detection
        tr = new();
        tr.sys_mode_select = 2'b01;
        tr.motion_sensor   = 1'b1;
        tr.print("TEST 4 - INTRUSION");
        drv.drive(tr);
        #100;

        $display("\n==================================================");
        $display("      ALL OOP TESTBENCH CASES EXECUTED CLEANLY    ");
        $display("==================================================");
    endtask
endclass

// ----------------------------------------------------------------------------
// Top Verification Module Wrapper
// ----------------------------------------------------------------------------
module smart_home_soc_top_tb;

    logic clk;
    logic rst_n;

    // 50 MHz Clock Generation
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Interface Instance
    soc_if vif (.clk(clk), .rst_n(rst_n));

    // Top-Level DUT Instantiation
    smart_home_soc #(
        .clk_freq_hz_p(50_000_000),
        .data_width_p(8)
    ) dut (
        .clk_i                (vif.clk),
        .rst_n_i              (vif.rst_n),
        .temp_sensor_i        (vif.temp_sensor),
        .light_sensor_i       (vif.light_sensor),
        .sys_mode_select_i    (vif.sys_mode_select),
        .user_temp_thresh_i   (vif.user_temp_thresh),
        .arm_system_i         (vif.arm_system),
        .disarm_system_i      (vif.disarm_system),
        .motion_sensor_i      (vif.motion_sensor),
        .doorbell_i           (vif.doorbell),
        .cooling_actuator_o   (vif.cooling_actuator),
        .overheat_buzzer_o    (vif.overheat_buzzer),
        .smart_lighting_o     (vif.smart_lighting),
        .strobe_led_o         (vif.strobe_led),
        .auditory_alarm_o     (vif.auditory_alarm),
        .servo_gate_pwm_o     (vif.servo_gate_pwm),
        .gate_status_led_o    (vif.gate_status_led),
        .current_sys_mode_o   (vif.current_sys_mode)
    );

    // Dynamic Test Execution Handle
    Environment env;

    initial begin
        // Setup Waveform Dumping (ModelSim / Vivado / VCS)
        $dumpfile("smart_home_soc_top_tb.vcd");
        $dumpvars(0, smart_home_soc_top_tb);

        rst_n = 0;
        #40;
        rst_n = 1;

        // Instantiate OOP Environment Object & Run Verification
        env = new(vif);
        env.run_all_tests();

        $finish;
    end

endmodule
