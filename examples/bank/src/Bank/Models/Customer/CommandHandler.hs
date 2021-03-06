{-# LANGUAGE TemplateHaskell #-}

module Bank.Models.Customer.CommandHandler
  ( CustomerCommand (..)
  , customerCommandHandler
  ) where

import SumTypes.TH

import Eventful

import Bank.Models.Customer.Commands
import Bank.Models.Customer.Events
import Bank.Models.Customer.Projection

constructSumType "CustomerCommand" (defaultSumTypeOptions { sumTypeOptionsTagOptions = AppendTypeNameToTags }) customerCommands

handleCustomerCommand :: Customer -> CustomerCommand -> [CustomerEvent]
handleCustomerCommand customer (CreateCustomerCustomerCommand (CreateCustomer name)) =
  case customerName customer of
    Nothing -> [CustomerCreatedCustomerEvent $ CustomerCreated name]
    Just _ -> [CustomerCreationRejectedCustomerEvent $ CustomerCreationRejected "Customer already exists"]

customerCommandHandler :: CommandHandler Customer CustomerEvent CustomerCommand
customerCommandHandler = CommandHandler handleCustomerCommand customerProjection
