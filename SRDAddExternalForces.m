classdef SRDAddExternalForces < handle
    properties
        SymbolicEngine;
        
        ForwardDynamicsStructure;
        
        vars;
    end
    methods
        % class constructor
        % initializes properties s and calls the superclass constructor.
        function obj = SRDAddExternalForces(SymbolicEngine)
            obj.SymbolicEngine = SymbolicEngine;
        end
        
        % This function generates symbolic expressions eeded to add
        % external force. To use them - call .UpdateModel() on every
        % iteration
        %
        %
        %Force - symbolic expression for the added generilized force; 
        %
        %vars - parameters defining the force (for example, Cartesian
        %components of the force producing the gen. Force.
        function AddForce(obj, Force, vars)
            timerVal = tic;

            disp('Started calculating the right hand side of the manipulator equations - with external forces');
            obj.ForwardDynamicsStructure.RightHandSide_ofManipulatorEq = ...
                obj.SymbolicEngine.ForwardDynamicsStructure.RightHandSide_ofManipulatorEq + Force;
            
            disp('Started calculating the skew vector (forces for the computed torque controller) - with external forces');
            obj.ForwardDynamicsStructure.ForcesForComputedTorqueController = ...
                obj.SymbolicEngine.ForwardDynamicsStructure.ForcesForComputedTorqueController + Force;
            
            disp('Finished updating symbolic exprssions to take into account external forces');
            
            
            disp('Started generating Right Hand Side of Manipulator Eq function - with external forces');
            matlabFunction(obj.ForwardDynamicsStructure.RightHandSide_ofManipulatorEq, 'File', ...
                'g_dynamics_RHS_ext', 'Vars', {obj.SymbolicEngine.q, obj.SymbolicEngine.v, obj.SymbolicEngine.u, vars}, ...
                'Optimize', obj.SymbolicEngine.ToOptimizeFunctions);
            
            disp('Started generating function for forces for the computed torque controller - with external forces');
            matlabFunction(obj.ForwardDynamicsStructure.ForcesForComputedTorqueController, 'File', ...
                'g_control_ForcesForComputedTorqueController_ext', 'Vars', {obj.SymbolicEngine.q, obj.SymbolicEngine.v, vars}, ...
                'Optimize', obj.SymbolicEngine.ToOptimizeFunctions); 
            
            disp('Finished generating functions to take into account external forces');

            obj.vars = vars;
            
            toc(timerVal);
        end
        
        %updates model functions in the SRDModelHandler
        %
        %value - value of parameters vars that are currently acting
        function UpdateModel(~, value, ModelHandler)
            
            ModelHandler.g_dynamics_RHS = @(q, v, u) g_dynamics_RHS_ext(q, v, u, value);
            ModelHandler.ForcesForComputedTorqueController = @(q, v) g_control_ForcesForComputedTorqueController_ext(q, v, value);
            
        end
    end
end
